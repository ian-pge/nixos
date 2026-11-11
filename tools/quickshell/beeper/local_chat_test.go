package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func waitLocal(t *testing.T, b *backend, check func([]localMessage, bool) bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		b.mu.Lock()
		ok := check(b.state.LocalMessages, b.localCancel != nil)
		b.mu.Unlock()
		if ok {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatal("local conversation did not reach the expected state")
}

func TestLocalChatStreamsPersistsAndUsesOnlyItsHistory(t *testing.T) {
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) { t.Error("local chat contacted Beeper") })
	b.client = nil // Local chat works without Beeper credentials.
	b.state.Drafts["private-remote-chat"] = draft{Text: "remote secret"}
	payloads := make(chan object, 2)
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body object
		json.NewDecoder(r.Body).Decode(&body)
		payloads <- body
		jsonResponse(w, object{"message": object{"content": "Bonjour "}})
		w.(http.Flusher).Flush()
		<-release
		jsonResponse(w, object{"message": object{"content": "Ian"}, "done": true})
	}))
	defer server.Close()
	b.localURL = server.URL
	if _, err := b.handle(b.ctx, "send", parameters{ChatID: localChatID, Text: "Salut"}); err != nil {
		t.Fatal(err)
	}
	first := <-payloads
	if first["model"] != localModel || first["think"] != false || first["stream"] != true {
		t.Fatalf("wrong request: %v", first)
	}
	raw, _ := json.Marshal(first)
	if strings.Contains(string(raw), "remote secret") || len(first["messages"].([]any)) != 2 {
		t.Fatalf("leaked context: %s", raw)
	}
	waitLocal(t, b, func(rows []localMessage, running bool) bool { return running && rows[1].Content == "Bonjour " })
	if _, err := b.sendLocal(parameters{Text: "duplicate"}); err == nil {
		t.Fatal("accepted overlapping generation")
	}
	close(release)
	waitLocal(t, b, func(rows []localMessage, running bool) bool {
		return !running && rows[1].Content == "Bonjour Ian" && rows[1].State == "complete"
	})
	if _, err := b.sendLocal(parameters{Text: "Et ensuite ?"}); err != nil {
		t.Fatal(err)
	}
	second := <-payloads
	context := second["messages"].([]any)
	if len(context) != 4 || context[2].(map[string]any)["content"] != "Bonjour Ian" {
		t.Fatalf("lost multi-turn context: %v", context)
	}
	waitLocal(t, b, func(rows []localMessage, running bool) bool { return !running && len(rows) == 4 })
	restored, err := newBackend(b.ctx, io.Discard, b.stateDir, false)
	if err != nil {
		t.Fatal(err)
	}
	if len(restored.state.LocalMessages) != 4 || restored.state.Drafts["private-remote-chat"].Text != "remote secret" {
		t.Fatal("state was not preserved")
	}
	info, _ := os.Stat(filepath.Join(b.stateDir, "state.json"))
	if info.Mode().Perm() != 0600 {
		t.Fatal("history is not private")
	}
}

func TestLocalChatCancellationKeepsPartialReply(t *testing.T) {
	b, _ := testBackend(t, nil)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, object{"message": object{"content": "Partial reply"}})
		w.(http.Flusher).Flush()
		<-r.Context().Done()
	}))
	defer server.Close()
	b.localURL = server.URL
	if _, err := b.sendLocal(parameters{Text: "Hello"}); err != nil {
		t.Fatal(err)
	}
	waitLocal(t, b, func(rows []localMessage, running bool) bool { return rows[1].Content == "Partial reply" })
	b.handle(b.ctx, "ollamaCancel", parameters{})
	waitLocal(t, b, func(rows []localMessage, running bool) bool {
		return !running && rows[1].State == "stopped" && rows[1].Content == "Partial reply"
	})
}

func TestLocalChatTruncatedStreamIsNotSuccess(t *testing.T) {
	b, _ := testBackend(t, nil)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		jsonResponse(w, object{"message": object{"content": "Incomplete"}})
	}))
	defer server.Close()
	b.localURL = server.URL
	b.sendLocal(parameters{Text: "Hello"})
	waitLocal(t, b, func(rows []localMessage, running bool) bool {
		return !running && rows[1].State == "failed" && rows[1].Content == "Incomplete"
	})
}

func TestLocalChatRejectsRedirectAndAttachments(t *testing.T) {
	b, _ := testBackend(t, nil)
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { t.Error("followed redirect") }))
	defer target.Close()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, target.URL, http.StatusTemporaryRedirect)
	}))
	defer server.Close()
	b.localURL = server.URL
	if _, err := b.sendLocal(parameters{Text: "Hello", Attachment: &attachment{Path: "/tmp/private"}}); err == nil {
		t.Fatal("accepted attachment")
	}
	b.sendLocal(parameters{Text: "Hello"})
	waitLocal(t, b, func(rows []localMessage, running bool) bool { return !running && rows[1].State == "failed" })
}

func TestLocalChatRestoresInterruptedGenerationAndPaginates(t *testing.T) {
	b, _ := testBackend(t, nil)
	for i := 0; i < 60; i++ {
		b.state.LocalMessages = append(b.state.LocalMessages, localMessage{ID: string(rune(100 + i)), Role: "user", Content: "hi"})
	}
	b.state.LocalMessages[59].Role = "assistant"
	b.state.LocalMessages[59].State = "generating"
	b.persistLocked()
	restored, err := newBackend(context.Background(), io.Discard, b.stateDir, false)
	if err != nil {
		t.Fatal(err)
	}
	if restored.state.LocalMessages[59].State != "interrupted" {
		t.Fatal("stale generation survived restart")
	}
	page, err := restored.handle(restored.ctx, "messages", parameters{ChatID: localChatID})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.(object)["items"].([]object)) != 50 || page.(object)["oldestCursor"] != "10" {
		t.Fatalf("bad page: %v", page)
	}
	page, err = restored.handle(restored.ctx, "messages", parameters{ChatID: localChatID, Cursor: "10"})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.(object)["items"].([]object)) != 10 || page.(object)["hasMore"] != false {
		t.Fatal("bad older page")
	}
}
