package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"sync/atomic"
	"testing"
)

func TestArchiveUsesPublicEndpointWithExplicitTrueAndFalse(t *testing.T) {
	for _, archived := range []bool{true, false} {
		var calls atomic.Int32
		b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			if r.Method != http.MethodPost || r.URL.EscapedPath() != "/v1/chats/chat%2F%23/archive" {
				t.Errorf("unexpected archive route: %s %s", r.Method, r.URL.EscapedPath())
			}
			var body object
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil || len(body) != 1 || body["archived"] != archived {
				t.Errorf("archive needs exactly the requested flag: %#v, %v", body, err)
			}
			w.WriteHeader(http.StatusNoContent)
		})
		result, err := b.handle(b.ctx, "archive", parameters{ChatID: "chat/#", Archived: &archived})
		if err != nil {
			t.Fatal(err)
		}
		if value, ok := result.(object); !ok || len(value) != 0 {
			t.Fatalf("unexpected archive response: %#v", result)
		}
		if calls.Load() != 1 {
			t.Fatalf("archive must not mark read, delete or make extra writes: %d calls", calls.Load())
		}
	}
}

func TestArchiveRejectsMissingTargetOrState(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) { t.Error("invalid archive request reached the API") })
	archived := true
	for _, params := range []parameters{{ChatID: "chat"}, {Archived: &archived}} {
		if _, err := b.handle(b.ctx, "archive", params); err == nil {
			t.Fatal("missing archive parameters accepted")
		}
	}
}

func TestArchivePreservesAPIErrorsWithoutEmittingSuccess(t *testing.T) {
	for _, tc := range []struct {
		status int
		code   string
	}{{http.StatusForbidden, "unauthorized"}, {http.StatusInternalServerError, "api_error"}} {
		var calls atomic.Int32
		b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
			calls.Add(1)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(tc.status)
			_, _ = io.WriteString(w, `{"message":"Archive refused"}`)
		})
		var events bytes.Buffer
		b.out = &events
		archived := true
		if _, err := b.handle(b.ctx, "archive", parameters{ChatID: "chat", Archived: &archived}); err == nil || safeError(err).Code != tc.code {
			t.Fatalf("HTTP %d must remain an API error: %v", tc.status, err)
		}
		if calls.Load() != 1 || events.Len() != 0 {
			t.Fatalf("failed archive must not retry or emit success: %d calls, events %q", calls.Load(), events.String())
		}
	}
}

func TestDemoArchiveChangesOnlyArchiveState(t *testing.T) {
	b, err := newBackend(context.Background(), io.Discard, t.TempDir(), true)
	if err != nil {
		t.Fatal(err)
	}
	chat := b.demoChats[0]
	chat["isMarkedUnread"] = true
	before, _ := json.Marshal(b.demoMessages)
	unread := chat["unreadCount"]
	for _, archived := range []bool{true, false} {
		if _, err := b.handle(b.ctx, "archive", parameters{ChatID: textField(chat, "id"), Archived: &archived}); err != nil {
			t.Fatal(err)
		}
		if boolField(chat, "isArchived") != archived || !boolField(chat, "isMarkedUnread") || chat["unreadCount"] != unread {
			t.Fatal("archive changed unread state")
		}
		after, _ := json.Marshal(b.demoMessages)
		if string(after) != string(before) {
			t.Fatal("archive changed messages or read receipts")
		}
	}
}
