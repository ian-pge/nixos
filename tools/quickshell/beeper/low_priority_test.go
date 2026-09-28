package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

func TestLowPriorityUsesNativeUpdateWithExplicitTrueAndFalse(t *testing.T) {
	for _, lowPriority := range []bool{true, false} {
		var calls atomic.Int32
		b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			if r.Method != http.MethodPatch || r.URL.EscapedPath() != "/v1/chats/chat%2F%23" {
				t.Errorf("unexpected priority route: %s %s", r.Method, r.URL.EscapedPath())
			}
			var body object
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil || len(body) != 1 || body["isLowPriority"] != lowPriority {
				t.Errorf("update must send only the requested native flag: %#v, %v", body, err)
			}
			jsonResponse(w, object{"id": "chat/#", "isLowPriority": lowPriority, "isMuted": true, "isMarkedUnread": true, "unreadCount": 3})
		})
		result, err := b.handle(b.ctx, "updateChat", parameters{ChatID: "chat/#", Changes: object{"isLowPriority": lowPriority}})
		if err != nil {
			t.Fatal(err)
		}
		var chat object
		if err := json.Unmarshal(result.(json.RawMessage), &chat); err != nil || chat["isLowPriority"] != lowPriority || chat["unreadCount"] != float64(3) || !boolField(chat, "isMuted") {
			t.Fatalf("native reply was changed: %#v, %v", chat, err)
		}
		if calls.Load() != 1 {
			t.Fatalf("priority must not mark read or issue extra writes: %d calls", calls.Load())
		}
	}
}

func TestLowPriorityRejectsInvalidTargetFlagsAndRemovedArchiveAction(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) { t.Error("invalid update reached Beeper") })
	for _, p := range []parameters{
		{Changes: object{"isLowPriority": true}},
		{ChatID: "chat", Changes: object{"isLowPriority": "true"}},
		{ChatID: "chat", Changes: object{"isLowPriority": nil}},
		{ChatID: "chat", Changes: object{"isArchived": true}},
	} {
		if _, err := b.handle(b.ctx, "updateChat", p); err == nil {
			t.Fatal("invalid update accepted")
		}
	}
	if _, err := b.handle(b.ctx, "archive", parameters{ChatID: "chat"}); err == nil {
		t.Fatal("the removed archive action must not reach Beeper")
	}
}

func TestLowPriorityPreservesAPIErrorsWithoutEmittingSuccess(t *testing.T) {
	for _, tc := range []struct {
		status int
		code   string
	}{{http.StatusForbidden, "unauthorized"}, {http.StatusInternalServerError, "api_error"}} {
		var calls atomic.Int32
		b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(tc.status)
			_, _ = io.WriteString(w, `{"message":"Low Priority refused"}`)
		})
		var events bytes.Buffer
		b.out = &events
		if _, err := b.handle(b.ctx, "updateChat", parameters{ChatID: "chat", Changes: object{"isLowPriority": true}}); err == nil || safeError(err).Code != tc.code {
			t.Fatalf("HTTP %d must remain an API error: %v", tc.status, err)
		}
		if calls.Load() != 1 || events.Len() != 0 {
			t.Fatalf("failed update must not retry or emit success: %d calls, events %q", calls.Load(), events.String())
		}
	}
}

func TestCatalogAndUnreadCountsFollowNativePriorityAcrossRestarts(t *testing.T) {
	var lowPriority atomic.Bool
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/v1/chats" {
			t.Errorf("unexpected write: %s %s", r.Method, r.URL.Path)
		}
		jsonResponse(w, object{"items": []object{{"id": "chat", "network": "Telegram", "title": "Native title",
			"isLowPriority": lowPriority.Load(), "isMarkedUnread": true, "unreadCount": 9,
			"preview": object{"id": "new-message", "text": "Fresh activity"}}},
			"hasMore": false, "oldestCursor": "opaque + /&"})
	})
	for _, value := range []bool{false, true, false} {
		lowPriority.Store(value) // Another Beeper client changes the priority.
		result, err := b.handle(b.ctx, "chats", parameters{})
		if err != nil {
			t.Fatal(err)
		}
		var page struct {
			Items        []object `json:"items"`
			OldestCursor string   `json:"oldestCursor"`
		}
		if err := json.Unmarshal(result.(json.RawMessage), &page); err != nil || len(page.Items) != 1 || boolField(page.Items[0], "isLowPriority") != value || page.OldestCursor != "opaque + /&" {
			t.Fatalf("native catalog was changed: %#v, %v", page, err)
		}
		counts, err := b.unreadCounts(b.ctx)
		if err != nil {
			t.Fatal(err)
		}
		main, low := counts["counts"].(map[string]int)["Telegram"], counts["lowPriorityCounts"].(map[string]int)["Telegram"]
		if main+low != 1 || (low == 1) != value {
			t.Fatalf("counts did not follow native priority: %#v", counts)
		}
		restarted, err := newBackend(b.ctx, io.Discard, b.stateDir, false)
		if err != nil {
			t.Fatal(err)
		}
		restarted.client = b.client
		b = restarted
	}
}

func TestLegacyArchiveStateIsIgnoredWithoutLosingDrafts(t *testing.T) {
	dir := t.TempDir()
	legacy := `{"version":1,"drafts":{"chat":{"text":"Keep draft"}},"pending":{"p":"chat"},"archives":{"chat":true}}`
	if err := os.WriteFile(filepath.Join(dir, "state.json"), []byte(legacy), 0600); err != nil {
		t.Fatal(err)
	}
	s, err := loadState(dir, false)
	if err != nil || s.Drafts["chat"].Text != "Keep draft" || s.Pending["p"] != "chat" {
		t.Fatalf("legacy state lost unrelated data: %#v, %v", s, err)
	}
	data, err := json.Marshal(s)
	if err != nil || bytes.Contains(data, []byte("archives")) || bytes.Contains(data, []byte("isLowPriority")) {
		t.Fatalf("placement must no longer be persisted: %s, %v", data, err)
	}
}

func TestDemoLowPriorityPreservesMessagesAndUnreadState(t *testing.T) {
	b, err := newBackend(context.Background(), io.Discard, t.TempDir(), true)
	if err != nil {
		t.Fatal(err)
	}
	chat := b.demoChats[0]
	chat["isMarkedUnread"] = true
	before, _ := json.Marshal(b.demoMessages)
	unread := chat["unreadCount"]
	for _, lowPriority := range []bool{true, false} {
		if _, err := b.handle(b.ctx, "updateChat", parameters{ChatID: textField(chat, "id"), Changes: object{"isLowPriority": lowPriority}}); err != nil {
			t.Fatal(err)
		}
		if boolField(chat, "isLowPriority") != lowPriority || !boolField(chat, "isMarkedUnread") || chat["unreadCount"] != unread {
			t.Fatal("priority update changed unread state")
		}
		after, _ := json.Marshal(b.demoMessages)
		if !bytes.Equal(after, before) {
			t.Fatal("priority update changed messages or read receipts")
		}
	}
}

func TestLowPriorityNotificationsOnlyAllowMentionsAndOwnReplies(t *testing.T) {
	for _, tc := range []struct {
		name       string
		message    object
		snoozed    bool
		ownReply   bool
		wantNotify bool
	}{
		{"ordinary", object{}, false, false, false},
		{"someone-else", object{"mentions": []any{"other"}}, false, false, false},
		{"self", object{"mentions": []any{"self"}}, false, false, true},
		{"room", object{"mentions": []any{"@room"}}, false, false, true},
		{"own-reply", object{"linkedMessageID": "parent"}, false, true, true},
		{"other-reply", object{"linkedMessageID": "parent"}, false, false, false},
		{"snoozed", object{"mentions": []any{"self"}}, true, false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodGet {
					t.Error("notification evaluation must not change chat state")
				}
				switch r.URL.Path {
				case "/v1/chats/chat":
					chat := object{"id": "chat", "accountID": "account", "isLowPriority": true, "isMuted": false}
					if tc.snoozed {
						chat["snooze"] = object{"snoozeUntil": time.Now().Add(time.Hour).Format(time.RFC3339Nano)}
					}
					jsonResponse(w, chat)
				case "/v1/accounts/account":
					jsonResponse(w, object{"user": object{"id": "self"}})
				case "/v1/chats/chat/messages/parent":
					jsonResponse(w, object{"id": "parent", "isSender": tc.ownReply})
				default:
					t.Errorf("unexpected read: %s", r.URL.Path)
					w.WriteHeader(http.StatusNotFound)
				}
			})
			n := &fakeNotifications{}
			b.notifications = n
			message := object{"id": "new", "type": "TEXT", "timestamp": time.Now().Format(time.RFC3339Nano)}
			for key, value := range tc.message {
				message[key] = value
			}
			b.considerMessage(b.ctx, "chat", message, time.Now().Add(-time.Minute))
			if (n.count() == 1) != tc.wantNotify {
				t.Fatalf("unexpected notification count: %d", n.count())
			}
		})
	}
}
