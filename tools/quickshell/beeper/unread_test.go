package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"sync/atomic"
	"testing"
)

func TestChatStatesCoversEveryPageWithoutCountingMessagesOrDuplicates(t *testing.T) {
	var requests atomic.Int32
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.Method != http.MethodGet || r.URL.Path != "/v1/chats" {
			t.Errorf("counter must only read the public catalog: %s %s", r.Method, r.URL.Path)
		}
		switch r.URL.Query().Get("cursor") {
		case "":
			jsonResponse(w, object{"items": []object{
				{"id": "a", "network": "WhatsApp", "unreadCount": 17},
				{"id": "b", "network": "WhatsApp", "unreadCount": 0, "isMarkedUnread": true, "isLowPriority": true},
				{"id": "low", "network": "Telegram", "unreadCount": 8, "isLowPriority": true},
				{"id": "muted", "network": "Signal", "unreadCount": 2, "isMarkedUnread": true, "isMuted": true},
				{"id": "quiet", "network": "Signal", "unreadCount": 2, "isLowPriority": true},
			}, "hasMore": true, "oldestCursor": "opaque + /&"})
		case "opaque + /&":
			if r.URL.Query().Get("direction") != "before" {
				t.Error("pagination direction was lost")
			}
			jsonResponse(w, object{"items": []object{
				{"id": "a", "network": "WhatsApp", "unreadCount": 30},
				{"id": "c", "network": "Telegram", "unreadCount": 1},
				{"id": "d", "network": "Google Messages", "isMarkedUnread": true},
				{"id": "read", "network": "Signal", "unreadCount": 0},
			}, "hasMore": false})
		default:
			t.Errorf("unexpected cursor: %q", r.URL.Query().Get("cursor"))
			jsonResponse(w, object{"items": []object{}, "hasMore": false})
		}
	})
	result, err := b.handle(b.ctx, "chatStates", parameters{})
	if err != nil {
		t.Fatal(err)
	}
	encoded, _ := json.Marshal(result)
	var snapshot struct {
		Items []object `json:"items"`
	}
	if err := json.Unmarshal(encoded, &snapshot); err != nil {
		t.Fatal(err)
	}
	if len(snapshot.Items) != 8 {
		t.Fatalf("want eight unique chats, including read chats, got %d", len(snapshot.Items))
	}
	byID := map[string]object{}
	for _, chat := range snapshot.Items {
		byID[textField(chat, "id")] = chat
	}
	if byID["a"]["unreadCount"] != float64(30) || byID["read"]["unreadCount"] != float64(0) {
		t.Fatal("the complete state must retain actual counts, including zero")
	}
	if !boolField(byID["b"], "isMarkedUnread") || !boolField(byID["b"], "isLowPriority") {
		t.Fatal("manual unread and priority flags must be present in the same record")
	}
	if requests.Load() != 2 {
		t.Fatalf("expected both pages, got %d", requests.Load())
	}
}

func TestChatStatesNeverReportsAPartialTotalOnPaginationFailure(t *testing.T) {
	for _, mode := range []string{"repeat", "missing", "http"} {
		t.Run(mode, func(t *testing.T) {
			var requests atomic.Int32
			b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
				requests.Add(1)
				if mode == "http" && r.URL.Query().Get("cursor") != "" {
					w.WriteHeader(http.StatusServiceUnavailable)
					return
				}
				cursor := "next"
				if mode == "missing" {
					cursor = ""
				}
				jsonResponse(w, object{"items": []object{{"id": "a", "unreadCount": 1}}, "hasMore": true, "oldestCursor": cursor})
			})
			if result, err := b.chatStates(b.ctx); err == nil || result != nil {
				t.Fatalf("partial counts must be rejected: %#v, %v", result, err)
			}
			if requests.Load() > 2 {
				t.Fatal("cursor failure must not create a loop")
			}
		})
	}
}

func TestChatStatesHonorsCancellation(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("a canceled count must not start a catalog scan")
	})
	ctx, cancel := context.WithCancel(b.ctx)
	cancel()
	if _, err := b.handle(ctx, "chatStates", parameters{}); err == nil {
		t.Fatal("expected cancellation")
	}
}

func TestDemoChatStatesIncludesReadAndManuallyUnreadChats(t *testing.T) {
	b, err := newBackend(context.Background(), io.Discard, t.TempDir(), true)
	if err != nil {
		t.Fatal(err)
	}
	b.demoChats = []object{
		{"id": "read", "network": "Telegram", "unreadCount": 0},
		{"id": "manual", "network": "WhatsApp", "isMarkedUnread": true, "isLowPriority": true},
	}
	result, err := b.handleDemo("chatStates", parameters{})
	if err != nil {
		t.Fatal(err)
	}
	items := result.(object)["items"].([]object)
	if len(items) != 2 || items[0]["unreadCount"] != 0 || !boolField(items[1], "isMarkedUnread") || !boolField(items[1], "isLowPriority") {
		t.Fatalf("incomplete demo state: %#v", items)
	}
}

func TestReadStateRequiresConfirmationAndNormalizesOptionalFalse(t *testing.T) {
	for _, raw := range []string{
		`{}`, `{"id":"other","unreadCount":0}`, `{"id":"chat"}`,
		`{"id":"chat","unreadCount":-1}`, `{"id":"chat","unreadCount":0.5}`,
		`{"id":"chat","unreadCount":0,"isMarkedUnread":"false"}`,
	} {
		if _, err := confirmedReadState("chat", json.RawMessage(raw)); err == nil {
			t.Errorf("accepted invalid confirmation: %s", raw)
		}
	}
	raw, err := confirmedReadState("chat", json.RawMessage(`{"id":"chat","unreadCount":0}`))
	if err != nil {
		t.Fatal(err)
	}
	var chat object
	if err := json.Unmarshal(raw, &chat); err != nil {
		t.Fatal(err)
	}
	if chat["isMarkedUnread"] != false {
		t.Fatal("omitted optional flag must become false")
	}
}
