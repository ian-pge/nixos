package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	beeper "github.com/beeper/desktop-api-go/v5"
	"github.com/beeper/desktop-api-go/v5/option"
	"github.com/gorilla/websocket"
)

func testBackend(t *testing.T, handler http.HandlerFunc) (*backend, *httptest.Server) {
	t.Helper()
	t.Setenv("BEEPER_API_URL", "")
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	b, err := newBackend(ctx, io.Discard, t.TempDir(), false)
	if err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	c := beeper.NewClient(option.WithBaseURL(server.URL+"/"), option.WithAccessToken("test-token"), option.WithMaxRetries(0))
	b.client = &c
	b.baseURL = server.URL + "/"
	return b, server
}
func jsonResponse(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func TestJSONLFramingAndDemoIsolation(t *testing.T) {
	t.Setenv("BEEPER_API_URL", "")
	dir := filepath.Join(t.TempDir(), "must-not-exist")
	var out bytes.Buffer
	b, err := newBackend(context.Background(), &out, dir, true)
	if err != nil {
		t.Fatal(err)
	}
	input := `not-json
{"id":1,"method":"saveDraft","params":{"chatID":"demo-camille","text":"émoji 💙\nsecond line"}}
{"id":2,"method":"getDraft","params":{"chatID":"demo-camille"}}
{"id":3,"method":"status"}
`
	if err = b.serve(strings.NewReader(input)); err != nil {
		t.Fatal(err)
	}
	s := bufio.NewScanner(&out)
	responses := []object{}
	for s.Scan() {
		var m object
		if json.Unmarshal(s.Bytes(), &m) != nil {
			t.Fatal("invalid frame")
		}
		responses = append(responses, m)
	}
	if len(responses) != 4 {
		t.Fatalf("got %d responses", len(responses))
	}
	if textField(mapField(responses[2], "result"), "text") != "émoji 💙\nsecond line" {
		t.Fatalf("draft did not roundtrip: %v", responses[2])
	}
	if textField(mapField(responses[3], "result"), "state") != "demo" {
		t.Fatal("demo not labelled")
	}
	if _, err = os.Stat(dir); !os.IsNotExist(err) {
		t.Fatal("demo wrote local state")
	}
}
func TestPublicRoutesPreservePaginationAndEscapedIDs(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" {
			t.Error("missing token")
		}
		if r.URL.EscapedPath() != "/v1/chats/chat%2F%23/messages" {
			t.Errorf("unexpected escaped path %s", r.URL.EscapedPath())
		}
		if r.URL.Query().Get("cursor") != "opaque +/&=" || r.URL.Query().Get("direction") != "before" {
			t.Error("cursor changed")
		}
		jsonResponse(w, object{"items": []object{{"id": "m1", "seen": true}}, "hasMore": true, "oldestCursor": "next", "newestCursor": "first"})
	})
	r, err := b.handle(b.ctx, "messages", parameters{ChatID: "chat/#", Cursor: "opaque +/&=", Direction: "before"})
	if err != nil {
		t.Fatal(err)
	}
	var page object
	if json.Unmarshal(r.(json.RawMessage), &page) != nil {
		t.Fatal("invalid result")
	}
	if !boolField(page, "hasMore") || textField(page, "oldestCursor") != "next" {
		t.Fatal("lost pagination")
	}
}
func TestSendNeverRetriesAnUncertainResult(t *testing.T) {
	var calls atomic.Int32
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		w.WriteHeader(500)
		jsonResponse(w, object{"error": "upstream failed"})
	})
	_, err := b.handle(b.ctx, "send", parameters{ChatID: "chat", Text: "bonjour"})
	if safeError(err).Code != "send_uncertain" {
		t.Fatalf("got %v", err)
	}
	if calls.Load() != 1 {
		t.Fatalf("a mutation was repeated %d times", calls.Load())
	}
}

func TestCredentialsAreNeverReturnedInErrorsOrFollowRedirects(t *testing.T) {
	b, server := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(503)
		jsonResponse(w, object{"error": "private body test-token"})
	})
	var out bytes.Buffer
	b.out = &out
	if err := b.serve(strings.NewReader("{\"id\":1,\"method\":\"accounts\"}\n")); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out.String(), "test-token") || strings.Contains(out.String(), "private body") {
		t.Fatal("backend leaked API response diagnostics")
	}
	var followed atomic.Bool
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { followed.Store(true); jsonResponse(w, []object{}) }))
	defer destination.Close()
	redirect := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, destination.URL, http.StatusFound) }))
	defer redirect.Close()
	c := apiClient(redirect.URL+"/", "test-token")
	var result json.RawMessage
	if err := c.Get(b.ctx, "v1/accounts", nil, &result); err == nil {
		t.Fatal("redirect unexpectedly accepted")
	}
	if followed.Load() {
		t.Fatal("authenticated client followed redirect")
	}
	_ = server
}
func TestControlRequestsDoNotWaitForNetwork(t *testing.T) {
	release := make(chan struct{})
	started := make(chan struct{})
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) { close(started); <-release; jsonResponse(w, []object{}) })
	reader, writer := io.Pipe()
	b.out = writer
	defer reader.Close()
	defer writer.Close()
	done := make(chan error, 1)
	go func() {
		done <- b.serve(strings.NewReader("{\"id\":1,\"method\":\"accounts\"}\n{\"id\":2,\"method\":\"setView\",\"params\":{\"chatID\":\"visible\",\"focused\":true,\"atLatest\":true}}\n"))
	}()
	line := make(chan string, 1)
	go func() {
		s := bufio.NewScanner(reader)
		for s.Scan() {
			line <- s.Text()
		}
	}()
	select {
	case result := <-line:
		var m object
		_ = json.Unmarshal([]byte(result), &m)
		if m["id"] != float64(2) {
			t.Error("control did not complete first")
		}
	case <-time.After(2 * time.Second):
		t.Error("control blocked behind HTTP")
	}
	b.mu.Lock()
	view := b.view
	b.mu.Unlock()
	if view.ChatID != "visible" || !view.Focused {
		t.Error("focus update missing")
	}
	close(release)
	<-started
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("request did not complete")
	}
}
func TestDraftsStagingAndDeletionBoundaries(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) { t.Error("unexpected network") })
	original := filepath.Join(t.TempDir(), "photo.png")
	content := []byte("image content")
	if err := os.WriteFile(original, content, 0600); err != nil {
		t.Fatal(err)
	}
	a, err := b.stage(original, "")
	if err != nil {
		t.Fatal(err)
	}
	if a.Path == original || a.Type != "image" {
		t.Fatal("attachment not staged")
	}
	_, err = b.handle(b.ctx, "saveDraft", parameters{ChatID: "chat", Text: "brouillon", Attachment: a})
	if err != nil {
		t.Fatal(err)
	}
	s, err := loadState(b.stateDir, false)
	if err != nil {
		t.Fatal(err)
	}
	if s.Drafts["chat"].Attachment.Path != a.Path || s.Drafts["chat"].Text != "brouillon" {
		t.Fatal("draft not durable")
	}
	info, err := os.Stat(filepath.Join(b.stateDir, "state.json"))
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatal("private state permissions missing")
	}
	if b.discard(original) == nil {
		t.Fatal("would delete user file")
	}
	if b.discard(a.Path) == nil {
		t.Fatal("would delete in-use attachment")
	}
	_, _ = b.handle(b.ctx, "saveDraft", parameters{ChatID: "chat"})
	if err = b.discard(a.Path); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(original); err != nil {
		t.Fatal("original modified")
	}
}
func TestSendPreservesOriginalAttachmentName(t *testing.T) {
	var received object
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/assets/upload":
			jsonResponse(w, object{"uploadID": "uploaded-file"})
		case "/v1/chats/chat/messages":
			if err := json.NewDecoder(r.Body).Decode(&received); err != nil {
				t.Error(err)
			}
			jsonResponse(w, object{"chatID": "chat"})
		default:
			t.Errorf("unexpected request: %s", r.URL.Path)
		}
	})
	path := filepath.Join(t.TempDir(), "résumé.txt")
	if err := os.WriteFile(path, []byte("bonjour"), 0600); err != nil {
		t.Fatal(err)
	}
	a, err := b.stage(path, "")
	if err != nil {
		t.Fatal(err)
	}
	// Omitting a type must let Beeper detect it, not send an invalid empty enum.
	a.Type = ""
	if _, err = b.send(b.ctx, parameters{ChatID: "chat", Attachment: a}); err != nil {
		t.Fatal(err)
	}
	file := mapField(received, "attachment")
	if textField(file, "fileName") != "résumé.txt" || textField(file, "uploadID") != "uploaded-file" {
		t.Fatalf("attachment metadata lost: %#v", file)
	}
	if _, exists := file["type"]; exists {
		t.Fatal("empty type must be omitted")
	}
}

func TestUploadUsesOfficialMultipartEndpoint(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.URL.Path != "/v1/assets/upload" {
			t.Error("wrong endpoint")
		}
		f, _, err := r.FormFile("file")
		if err != nil {
			t.Error(err)
			return
		}
		defer f.Close()
		data, _ := io.ReadAll(f)
		if string(data) != "voice bytes" {
			t.Error("corrupted upload")
		}
		jsonResponse(w, object{"uploadID": "upload-1", "mimeType": "audio/ogg"})
	})
	file := filepath.Join(t.TempDir(), "vocal.ogg")
	_ = os.WriteFile(file, []byte("voice bytes"), 0600)
	r, err := b.upload(b.ctx, file)
	if err != nil || r.UploadID != "upload-1" {
		t.Fatalf("upload failed: %v", err)
	}
}

type capturedNotification struct {
	title, body string
	target      object
	silent      bool
}
type fakeNotifications struct {
	mu       sync.Mutex
	items    []capturedNotification
	received chan struct{}
}

func (n *fakeNotifications) send(title, body, icon string, target object, silent bool) {
	n.mu.Lock()
	n.items = append(n.items, capturedNotification{title, body, target, silent})
	n.mu.Unlock()
	if n.received != nil {
		select {
		case n.received <- struct{}{}:
		default:
		}
	}
}
func (n *fakeNotifications) close()     {}
func (n *fakeNotifications) count() int { n.mu.Lock(); defer n.mu.Unlock(); return len(n.items) }
func TestNotificationsAreDurableAndRespectVisibilityAndMute(t *testing.T) {
	var isMuted atomic.Bool
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, object{"id": "chat", "title": "Camille", "isMuted": isMuted.Load()})
	})
	n := &fakeNotifications{}
	b.notifications = n
	since := time.Now().Add(-time.Minute)
	m := func(id string) object {
		return object{"id": id, "text": "bonjour", "senderName": "Camille", "type": "TEXT", "timestamp": time.Now().Format(time.RFC3339Nano)}
	}
	b.considerMessage(b.ctx, "chat", m("one"), since)
	b.considerMessage(b.ctx, "chat", m("one"), since)
	if n.count() != 1 {
		t.Fatal("duplicate notification")
	}
	s, err := loadState(b.stateDir, false)
	if err != nil {
		t.Fatal(err)
	}
	b.state = s
	b.considerMessage(b.ctx, "chat", m("one"), since)
	if n.count() != 1 {
		t.Fatal("duplicate after restart")
	}
	b.view = parameters{ChatID: "chat", Focused: true, AtLatest: true}
	b.considerMessage(b.ctx, "chat", m("two"), since)
	if n.count() != 1 {
		t.Fatal("visible message notified")
	}
	b.view.Focused = false
	b.considerMessage(b.ctx, "chat", m("three"), since)
	if n.count() != 2 {
		t.Fatal("background view suppressed notification")
	}
	isMuted.Store(true)
	b.considerMessage(b.ctx, "chat", m("four"), since)
	if n.count() != 2 {
		t.Fatal("muted chat notified")
	}
}
func TestNotificationCandidatesExcludeHistoricalAndMutatedMessages(t *testing.T) {
	since := time.Now().Add(-time.Minute)
	for _, tc := range []struct {
		name   string
		change object
	}{{"own", object{"isSender": true}}, {"edit", object{"editedTimestamp": time.Now().Format(time.RFC3339Nano)}}, {"history", object{"timestamp": since.Add(-time.Hour).Format(time.RFC3339Nano)}}, {"reaction", object{"type": "REACTION"}}, {"deleted", object{"isDeleted": true}}, {"read", object{"isUnread": false}}, {"hidden", object{"isHidden": true}}} {
		t.Run(tc.name, func(t *testing.T) {
			m := object{"id": "message", "timestamp": time.Now().Format(time.RFC3339Nano), "type": "TEXT"}
			for k, v := range tc.change {
				m[k] = v
			}
			if notificationCandidate(m, since) {
				t.Fatal("should not notify")
			}
		})
	}
	if !muted(object{"snooze": object{"snoozeUntil": time.Now().Add(time.Hour).Format(time.RFC3339Nano)}}) {
		t.Fatal("snooze ignored")
	}
}
func TestResyncPaginatesSilentlyAndOnlySummarizesOnce(t *testing.T) {
	var calls atomic.Int32
	now := time.Now().Format(time.RFC3339Nano)
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		id := "first"
		more := true
		cursor := "next"
		if r.URL.Query().Get("cursor") == "next" {
			id = "second"
			more = false
			cursor = ""
		}
		jsonResponse(w, object{"items": []object{{"id": id, "unreadCount": 2, "preview": object{"id": "m-" + id, "timestamp": now}}}, "hasMore": more, "oldestCursor": cursor})
	})
	n := &fakeNotifications{}
	b.notifications = n
	if err := b.resync(b.ctx, b.client, false, time.Now().Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 2 || n.count() != 0 {
		t.Fatal("initial sync was not silent/paginated")
	}
	if err := b.resync(b.ctx, b.client, true, time.Now().Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	if n.count() != 0 {
		t.Fatal("already seen messages summarized again")
	}
	b.state.Seen = map[string]int64{}
	if err := b.resync(b.ctx, b.client, true, time.Now().Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	if n.count() != 1 || !n.items[0].silent {
		t.Fatal("missing silent catch-up summary")
	}
}
func TestWebSocketUsesDocumentedSubscriptionAndCancels(t *testing.T) {
	receivedSubscription := make(chan object, 1)
	upgrader := websocket.Upgrader{}
	b, server := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/accounts":
			jsonResponse(w, []object{})
		case "/v1/chats":
			jsonResponse(w, demoPage([]object{}))
		case "/v1/chats/chat":
			jsonResponse(w, object{"id": "chat", "title": "Camille"})
		case "/v1/ws":
			if r.Header.Get("Authorization") != "Bearer test-token" {
				t.Error("websocket not authenticated")
			}
			c, err := upgrader.Upgrade(w, r, nil)
			if err != nil {
				t.Error(err)
				return
			}
			defer c.Close()
			var sub object
			if c.ReadJSON(&sub) != nil {
				return
			}
			receivedSubscription <- sub
			_ = c.WriteJSON(object{"type": "ready", "version": 1})
			_ = c.WriteJSON(object{"type": "message.upserted", "seq": 1, "chatID": "chat", "entries": []object{{"id": "live", "text": "bonjour", "type": "TEXT", "timestamp": time.Now().Add(time.Second).Format(time.RFC3339Nano)}}})
			for {
				if _, _, err = c.ReadMessage(); err != nil {
					return
				}
			}
		default:
			t.Errorf("unexpected route %s", r.URL.Path)
		}
	})
	b.baseURL = server.URL + "/"
	n := &fakeNotifications{received: make(chan struct{}, 1)}
	b.notifications = n
	ctx, cancel := context.WithCancel(b.ctx)
	done := make(chan struct{})
	go func() { b.runStream(ctx, b.client, "test-token"); close(done) }()
	defer cancel()
	select {
	case sub := <-receivedSubscription:
		if textField(sub, "type") != "subscriptions.set" {
			t.Fatal("wrong subscription")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("did not subscribe")
	}
	select {
	case <-n.received:
	case <-time.After(3 * time.Second):
		t.Fatal("live message not notified")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("stream leaked after cancellation")
	}
}
