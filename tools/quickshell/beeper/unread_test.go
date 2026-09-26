package main

import (
	"context"
	"io"
	"net/http"
	"reflect"
	"sync/atomic"
	"testing"
)

func TestUnreadCountsCoversEveryPageWithoutCountingMessagesOrDuplicates(t *testing.T) {
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
				{"id": "b", "network": "WhatsApp", "unreadCount": 0, "isMarkedUnread": true, "isArchived": true},
				{"id": "archived", "network": "Telegram", "unreadCount": 8, "isArchived": true},
				{"id": "muted", "network": "Signal", "unreadCount": 2, "isMarkedUnread": true, "isMuted": true, "isLowPriority": true},
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
	result, err := b.handle(b.ctx, "unreadCounts", parameters{})
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]int{"WhatsApp": 2, "Telegram": 1, "Signal": 1, "Google Messages": 1}
	if got := result.(object)["counts"]; !reflect.DeepEqual(got, want) {
		t.Fatalf("conversation counts: got %#v, want %#v", got, want)
	}
	wantAll := map[string]int{"WhatsApp": 2, "Telegram": 2, "Signal": 1, "Google Messages": 1}
	if got := result.(object)["allCounts"]; !reflect.DeepEqual(got, wantAll) {
		t.Fatalf("archive-inclusive counts: got %#v, want %#v", got, wantAll)
	}
	wantArchived := map[string]int{"WhatsApp": 1, "Telegram": 1}
	if got := result.(object)["archivedCounts"]; !reflect.DeepEqual(got, wantArchived) {
		t.Fatalf("archive-only counts: got %#v, want %#v", got, wantArchived)
	}
	if requests.Load() != 2 {
		t.Fatalf("expected both pages, got %d", requests.Load())
	}
}

func TestUnreadCountsNeverReportsAPartialTotalOnPaginationFailure(t *testing.T) {
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
			if result, err := b.unreadCounts(b.ctx); err == nil || result != nil {
				t.Fatalf("partial counts must be rejected: %#v, %v", result, err)
			}
			if requests.Load() > 2 {
				t.Fatal("cursor failure must not create a loop")
			}
		})
	}
}

func TestUnreadCountsHonorsCancellation(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		t.Error("a canceled count must not start a catalog scan")
	})
	ctx, cancel := context.WithCancel(b.ctx)
	cancel()
	if _, err := b.handle(ctx, "unreadCounts", parameters{}); err == nil {
		t.Fatal("expected cancellation")
	}
}

func TestDemoUnreadCountsSeparatesArchivesAndIncludesManualReminders(t *testing.T) {
	b, err := newBackend(context.Background(), io.Discard, t.TempDir(), true)
	if err != nil {
		t.Fatal(err)
	}
	b.demoChats = []object{
		{"network": "Telegram", "unreadCount": 4},
		{"network": "Telegram", "unreadCount": 2, "isArchived": true},
		{"network": "WhatsApp", "isMarkedUnread": true, "isArchived": true},
		{"network": "Signal", "isArchived": true},
	}
	result, err := b.handleDemo("unreadCounts", parameters{})
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]int{"Telegram": 1, "WhatsApp": 1}
	if got := result.(object)["archivedCounts"]; !reflect.DeepEqual(got, want) {
		t.Fatalf("archive-only counts: got %#v, want %#v", got, want)
	}
}
