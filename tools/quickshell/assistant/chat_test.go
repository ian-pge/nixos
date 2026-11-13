package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// The test binary doubles as a scripted `pi --mode rpc`. It records its
// arguments and commands, and never contacts a model.
func TestMain(m *testing.M) {
	if os.Getenv("FAKE_PI_LOG") != "" {
		fakePi()
		return
	}
	os.Exit(m.Run())
}

func fakePi() {
	log, _ := os.OpenFile(os.Getenv("FAKE_PI_LOG"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	args, _ := json.Marshal(os.Args[1:])
	fmt.Fprintf(log, "args %s\n", args)
	out := json.NewEncoder(os.Stdout)
	emit := func(v any) { _ = out.Encode(v) }
	delta := func(text string) {
		emit(object{"type": "message_update", "assistantMessageEvent": object{"type": "text_delta", "contentIndex": 0, "delta": text}})
	}
	// Like pi: the first token can arrive in message_start, and message_end
	// carries the authoritative content.
	text := func(parts ...string) {
		emit(object{"type": "message_start", "message": object{"role": "assistant", "content": []object{{"type": "text", "text": parts[0]}}}})
		for _, part := range parts[1:] {
			delta(part)
		}
		emit(object{"type": "message_end", "message": object{"role": "assistant", "stopReason": "stop", "content": []object{{"type": "text", "text": strings.Join(parts, "")}}}})
	}
	commands := make(chan object)
	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			var command object
			if json.Unmarshal(scanner.Bytes(), &command) == nil {
				line, _ := json.Marshal(command)
				fmt.Fprintf(log, "command %s\n", line)
				commands <- command
			}
		}
		close(commands)
	}()
	for command := range commands {
		if command["type"] != "prompt" {
			continue
		}
		emit(object{"id": command["id"], "type": "response", "command": "prompt", "success": true, "data": object{"disposition": "started"}})
		message, _ := command["message"].(string)
		if strings.Contains(strings.Join(os.Args, " "), "--no-tools") {
			text(`{"text":"Les filles","explanations":[{"from":"fille","to":"filles","reason":"Après « les », le nom prend le pluriel."}]}`)
			emit(object{"type": "agent_settled", "aborted": false})
			continue
		}
		switch {
		case strings.Contains(message, "hang"):
			emit(object{"type": "message_start", "message": object{"role": "assistant", "content": []object{}}})
			delta("Partial")
			for next := range commands {
				if next["type"] == "abort" {
					emit(object{"type": "message_end", "message": object{"role": "assistant", "stopReason": "aborted"}})
					emit(object{"type": "agent_settled", "aborted": true})
					emit(object{"type": "response", "command": "abort", "success": true})
					break
				}
			}
		case strings.Contains(message, "tool"):
			text("Je regarde.")
			emit(object{"type": "tool_execution_start", "toolCallId": "1", "toolName": "bash", "args": object{"command": "ls `-la`\n /tmp"}})
			emit(object{"type": "tool_execution_end", "toolCallId": "1", "toolName": "bash", "isError": true})
			text("C'est fait.")
			emit(object{"type": "agent_settled", "aborted": false})
		case strings.Contains(message, "error"):
			emit(object{"type": "message_end", "message": object{"role": "assistant", "stopReason": "error", "errorMessage": "Usage limit reached"}})
			emit(object{"type": "agent_settled", "aborted": false})
		case strings.Contains(message, "crash"):
			emit(object{"type": "message_start", "message": object{"role": "assistant", "content": []object{{"type": "text", "text": "Avant"}}}})
			os.Exit(3)
		default:
			text("Bonjour ", "Ian")
			emit(object{"type": "agent_settled", "aborted": false})
		}
	}
}

func testBackend(t *testing.T) (*backend, string) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	b, err := newBackend(ctx, io.Discard, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { b.shutdown(); cancel() })
	logFile := filepath.Join(t.TempDir(), "pi.log")
	t.Setenv("FAKE_PI_LOG", logFile)
	exe, _ := os.Executable()
	b.piCommand = []string{exe}
	// The Nix build sandbox has no home folder.
	b.workDir = t.TempDir()
	b.chatURL = "http://127.0.0.1:1"
	return b, logFile
}

func jsonResponse(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func waitChat(t *testing.T, b *backend, key string, check func([]chatMessage, bool) bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		b.mu.Lock()
		ok := check(b.state.Conversations[key].Messages, b.runtime(key).run != nil)
		b.mu.Unlock()
		if ok {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	t.Fatalf("conversation %s did not reach the expected state: %+v", key, b.state.Conversations[key].Messages)
}

func piLog(t *testing.T, path string) (args [][]string, commands []object) {
	t.Helper()
	data, _ := os.ReadFile(path)
	for _, line := range strings.Split(string(data), "\n") {
		if rest, ok := strings.CutPrefix(line, "args "); ok {
			var a []string
			json.Unmarshal([]byte(rest), &a)
			args = append(args, a)
		} else if rest, ok := strings.CutPrefix(line, "command "); ok {
			var c object
			json.Unmarshal([]byte(rest), &c)
			commands = append(commands, c)
		}
	}
	return
}

func argValue(args []string, name string) string {
	for i, arg := range args {
		if arg == name && i+1 < len(args) {
			return args[i+1]
		}
	}
	return ""
}

func TestQwenIsReadOnlyAndOpenAIHasEveryTool(t *testing.T) {
	b, logFile := testBackend(t)
	b.screenshots = "Shots"
	for _, key := range []string{"qwen", "openai"} {
		if _, err := b.handle(b.ctx, "send", parameters{Conversation: key, Text: "Salut"}); err != nil {
			t.Fatal(err)
		}
		waitChat(t, b, key, func(rows []chatMessage, running bool) bool {
			return !running && len(rows) == 2 && rows[1].State == "complete"
		})
	}
	args, _ := piLog(t, logFile)
	if len(args) != 2 {
		t.Fatalf("expected one pi per conversation, got %v", args)
	}
	qwen, openai := args[0], args[1]
	if argValue(qwen, "--model") != "ollama/"+model || argValue(qwen, "--tools") != "read,grep,find,ls" || argValue(qwen, "--mode") != "rpc" {
		t.Fatalf("bad Qwen arguments: %v", qwen)
	}
	if argValue(openai, "--model") != "openai-codex/gpt-6.1-sol" || !strings.Contains(argValue(openai, "--tools"), "bash") {
		t.Fatalf("bad OpenAI arguments: %v", openai)
	}
	for _, a := range args {
		for _, isolation := range []string{"--no-extensions", "--no-skills", "--no-mcp", "--no-context-files"} {
			if !strings.Contains(strings.Join(a, " "), isolation) {
				t.Fatalf("pi loads unrelated resources: %v", a)
			}
		}
	}
	home, _ := os.UserHomeDir()
	shots := filepath.Join(home, "Shots")
	if !strings.Contains(argValue(openai, "--append-system-prompt"), shots) || strings.Contains(argValue(qwen, "--append-system-prompt"), "screenshot") {
		t.Fatalf("only GPT is told where the screenshots are: %v", openai)
	}
	if argValue(qwen, "--session-id") == argValue(openai, "--session-id") {
		t.Fatal("conversations share a session")
	}
}

func TestChatStreamsPersistsAndResumesItsSession(t *testing.T) {
	b, logFile := testBackend(t)
	b.state.Conversations["openai"].Draft = "unsent draft"
	if _, err := b.handle(b.ctx, "send", parameters{Conversation: "openai", Text: "Salut"}); err != nil {
		t.Fatal(err)
	}
	if _, err := b.send("openai", "duplicate"); err == nil {
		// The fake answers fast; a second send may only be accepted after it settled.
		b.mu.Lock()
		if len(b.state.Conversations["openai"].Messages) != 4 {
			b.mu.Unlock()
			t.Fatal("accepted an overlapping message")
		}
		b.mu.Unlock()
	}
	waitChat(t, b, "openai", func(rows []chatMessage, running bool) bool {
		return !running && rows[1].Content == "Bonjour Ian" && rows[1].State == "complete"
	})
	if len(b.state.Conversations["qwen"].Messages) != 0 {
		t.Fatal("conversations are not separate")
	}
	session := b.state.Conversations["openai"].SessionID
	b.shutdown()
	restored, err := newBackend(b.ctx, io.Discard, b.stateDir)
	if err != nil {
		t.Fatal(err)
	}
	restored.piCommand, restored.workDir = b.piCommand, b.workDir
	t.Cleanup(restored.shutdown)
	c := restored.state.Conversations["openai"]
	if len(c.Messages) < 2 || c.Draft != "unsent draft" || c.SessionID != session {
		t.Fatal("state was not preserved")
	}
	restored.send("openai", "Encore")
	waitChat(t, restored, "openai", func(rows []chatMessage, running bool) bool { return !running && rows[len(rows)-1].State == "complete" })
	args, _ := piLog(t, logFile)
	if argValue(args[len(args)-1], "--session-id") != session {
		t.Fatal("the pi session was not resumed after a restart")
	}
	info, _ := os.Stat(filepath.Join(b.stateDir, "state.json"))
	if info.Mode().Perm() != 0600 {
		t.Fatal("history is not private")
	}
}

func TestChatShowsToolCallsAndProviderErrors(t *testing.T) {
	b, _ := testBackend(t)
	b.send("openai", "tool please")
	waitChat(t, b, "openai", func(rows []chatMessage, running bool) bool { return !running && len(rows) == 2 })
	content := b.state.Conversations["openai"].Messages[1].Content
	if !strings.Contains(content, "Je regarde.\n\n> ▸ **bash** · `ls '-la' /tmp` — failed\n\nC'est fait.") {
		t.Fatalf("tool call not summarized: %q", content)
	}
	b.send("openai", "error please")
	waitChat(t, b, "openai", func(rows []chatMessage, running bool) bool { return !running && len(rows) == 4 })
	reply := b.state.Conversations["openai"].Messages[3]
	if reply.State != "failed" || !strings.Contains(reply.display()["text"].(string), "Usage limit reached") {
		t.Fatalf("provider error hidden: %+v", reply)
	}
}

func TestChatCancellationKeepsPartialReplyAndCrashFails(t *testing.T) {
	b, logFile := testBackend(t)
	b.send("qwen", "hang please")
	waitChat(t, b, "qwen", func(rows []chatMessage, running bool) bool { return running && rows[1].Content == "Partial" })
	b.handle(b.ctx, "cancel", parameters{Conversation: "qwen"})
	waitChat(t, b, "qwen", func(rows []chatMessage, running bool) bool {
		return !running && rows[1].State == "stopped" && rows[1].Content == "Partial"
	})
	_, commands := piLog(t, logFile)
	if commands[len(commands)-1]["type"] != "abort" {
		t.Fatal("stop did not abort pi")
	}
	b.send("qwen", "crash please")
	waitChat(t, b, "qwen", func(rows []chatMessage, running bool) bool {
		return !running && len(rows) == 4 && rows[3].State == "failed"
	})
	// The next message starts a new pi on the same session.
	b.send("qwen", "Hello")
	waitChat(t, b, "qwen", func(rows []chatMessage, running bool) bool {
		return !running && len(rows) == 6 && rows[5].State == "complete"
	})
}

func TestChatResetStartsANewSessionAndKeepsDraft(t *testing.T) {
	b, logFile := testBackend(t)
	b.state.Conversations["qwen"].Draft = "Unsent draft"
	b.send("qwen", "hang please")
	waitChat(t, b, "qwen", func(rows []chatMessage, running bool) bool { return running && rows[1].Content == "Partial" })
	old := b.state.Conversations["qwen"].SessionID
	result, err := b.handle(b.ctx, "reset", parameters{Conversation: "qwen"})
	if err != nil {
		t.Fatal(err)
	}
	snapshot := result.(object)
	if len(snapshot["items"].([]object)) != 0 || snapshot["generating"] != false || snapshot["resetRevision"] != snapshot["revision"] || snapshot["draft"] != "Unsent draft" {
		t.Fatalf("bad reset snapshot: %v", snapshot)
	}
	b.send("qwen", "Fresh question")
	waitChat(t, b, "qwen", func(rows []chatMessage, running bool) bool {
		return !running && len(rows) == 2 && rows[1].State == "complete"
	})
	args, _ := piLog(t, logFile)
	if session := argValue(args[len(args)-1], "--session-id"); session == old || session != b.state.Conversations["qwen"].SessionID {
		t.Fatal("reset kept the previous model context")
	}
	restored, err := newBackend(b.ctx, io.Discard, b.stateDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(restored.state.Conversations["qwen"].Messages) != 2 || restored.state.Conversations["qwen"].Draft != "Unsent draft" {
		t.Fatal("reset was not persisted or changed the draft")
	}
}

func TestChatResetFailurePreservesHistory(t *testing.T) {
	b, _ := testBackend(t)
	b.state.Conversations["qwen"].Messages = []chatMessage{{ID: "keep", Role: "user", Content: "Keep"}}
	blocked := filepath.Join(b.stateDir, "blocked")
	if err := os.WriteFile(blocked, nil, 0600); err != nil {
		t.Fatal(err)
	}
	b.stateDir = blocked
	if _, err := b.handle(b.ctx, "reset", parameters{Conversation: "qwen"}); err == nil {
		t.Fatal("reset reported success despite a storage failure")
	}
	if len(b.state.Conversations["qwen"].Messages) != 1 || b.runtime("qwen").resetRevision != 0 {
		t.Fatal("failed reset discarded history")
	}
}

func TestUnloadStopsQwenReplyThenUnloadsTheModel(t *testing.T) {
	b, _ := testBackend(t)
	payloads := make(chan object, 2)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body object
		json.NewDecoder(r.Body).Decode(&body)
		payloads <- body
		jsonResponse(w, object{"done": true, "done_reason": "unload"})
	}))
	defer server.Close()
	b.chatURL = server.URL
	b.send("qwen", "hang please")
	waitChat(t, b, "qwen", func(rows []chatMessage, running bool) bool { return running && rows[1].Content == "Partial" })
	result, err := b.handle(b.ctx, "unload", parameters{})
	if err != nil || result.(object)["unloaded"] != true {
		t.Fatalf("unload failed: %v %v", result, err)
	}
	payload := <-payloads
	if payload["model"] != model || payload["keep_alive"] != float64(0) {
		t.Fatalf("bad unload payload: %v", payload)
	}
	if rows := b.state.Conversations["qwen"].Messages; rows[1].State != "stopped" || b.unloading {
		t.Fatalf("unload did not stop the reply first: %+v", rows)
	}
	for _, response := range []string{`{"done":true,"done_reason":"stop"}`, `invalid json`} {
		failing := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, response) }))
		b.chatURL = failing.URL
		if _, err := b.handle(b.ctx, "unload", parameters{}); err == nil || b.unloading {
			t.Fatal("reported success for a failed unload or stayed busy")
		}
		failing.Close()
	}
}

func TestVersionOneStateMigratesToTheQwenConversation(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "state.json"), []byte(`{"version":1,"messages":[{"id":"a","role":"user","content":"ancien","timestamp":"2026-11-12T10:00:00Z"},{"id":"b","role":"assistant","content":"x","state":"generating"}],"draft":"brouillon"}`), 0600)
	b, err := newBackend(context.Background(), io.Discard, dir)
	if err != nil {
		t.Fatal(err)
	}
	qwen := b.state.Conversations["qwen"]
	if len(qwen.Messages) != 2 || qwen.Draft != "brouillon" || qwen.Messages[1].State != "interrupted" || qwen.SessionID == "" {
		t.Fatalf("v1 state not migrated: %+v", qwen)
	}
	if b.state.Version != 2 || b.state.Selected != "qwen" || len(b.state.Conversations["openai"].Messages) != 0 {
		t.Fatal("bad migrated state")
	}
}

func TestPaginationSearchAndEscaping(t *testing.T) {
	b, _ := testBackend(t)
	rows := []chatMessage{}
	for i := 0; i < 60; i++ {
		rows = append(rows, chatMessage{ID: fmt.Sprint(i), Role: "user", Content: "hi"})
	}
	rows[0] = chatMessage{ID: "0", Role: "user", Content: "<b>Été</b>\n  # pas un titre"}
	rows[1] = chatMessage{ID: "1", Role: "assistant", Content: "Un **résumé** rapide", State: "complete"}
	b.state.Conversations["qwen"].Messages = rows
	page, err := b.handle(b.ctx, "messages", parameters{Conversation: "qwen"})
	if err != nil || len(page.(object)["items"].([]object)) != 50 || page.(object)["oldestCursor"] != "10" {
		t.Fatalf("bad page: %v %v", page, err)
	}
	page, _ = b.handle(b.ctx, "messages", parameters{Conversation: "qwen", Cursor: "10"})
	if len(page.(object)["items"].([]object)) != 10 || page.(object)["hasMore"] != false {
		t.Fatal("bad older page")
	}
	if _, err := b.handle(b.ctx, "messages", parameters{Conversation: "qwen", Cursor: "61"}); err == nil {
		t.Fatal("accepted an invalid cursor")
	}
	if _, err := b.handle(b.ctx, "messages", parameters{Conversation: "mistral"}); err == nil {
		t.Fatal("accepted an unknown conversation")
	}
	user := rows[0].display()
	if html := user["html"].(string); !strings.Contains(html, "&lt;b&gt;") || strings.Contains(html, "<b>") || strings.Contains(html, "<h1>") {
		t.Fatalf("user text not literal: %v", html)
	}
	result, _ := b.handle(b.ctx, "search", parameters{Conversation: "qwen", Query: "ETE titre"})
	if ids := result.(object)["ids"].([]string); len(ids) != 1 || ids[0] != "0" {
		t.Fatalf("wrong matches: %v", ids)
	}
	result, _ = b.handle(b.ctx, "search", parameters{Conversation: "qwen", Query: "resume"})
	if ids := result.(object)["ids"].([]string); len(ids) != 1 || ids[0] != "1" {
		t.Fatalf("accent-insensitive search failed: %v", ids)
	}
	result, _ = b.handle(b.ctx, "search", parameters{Conversation: "openai", Query: "resume"})
	if ids := result.(object)["ids"].([]string); len(ids) != 0 {
		t.Fatal("search crossed conversations")
	}
}

func TestProtocolKeepsDraftsAndSelectionPerConversation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var output bytes.Buffer
	b, err := newBackend(ctx, &output, t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	input := strings.Join([]string{
		`{"id":1,"method":"saveDraft","params":{"conversation":"openai","text":"Brouillon GPT"}}`,
		`{"id":2,"method":"getDraft","params":{"conversation":"qwen"}}`,
		`{"id":3,"method":"select","params":{"conversation":"openai"}}`,
		`not json`,
		`{"id":4,"method":"unknown"}`,
		`{"id":5,"method":"send","params":{"conversation":"qwen","text":"   "}}`,
	}, "\n") + "\n"
	if err := b.serve(strings.NewReader(input)); err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(output.String()), "\n")
	if len(lines) != 6 || !strings.Contains(lines[1], `"text":""`) || !strings.Contains(lines[2], `"selected":"openai"`) ||
		!strings.Contains(lines[3], "invalid_request") || !strings.Contains(lines[4], "unknown_method") || !strings.Contains(lines[5], "invalid_params") {
		t.Fatalf("unexpected protocol output:\n%s", output.String())
	}
	restored, _ := newBackend(ctx, io.Discard, b.stateDir)
	status, _ := restored.handle(ctx, "status", parameters{Conversation: "openai"})
	if restored.state.Conversations["openai"].Draft != "Brouillon GPT" || status.(object)["selected"] != "openai" || status.(object)["draft"] != "Brouillon GPT" {
		t.Fatal("draft or selection was not persisted")
	}
}

func TestThinkingFlagCoversWaitsAndToolCalls(t *testing.T) {
	waiting := chatMessage{Role: "assistant", State: "generating"}.display()
	if waiting["thinking"] != true || waiting["text"] != "…" {
		t.Fatalf("an empty reply is not thinking: %v", waiting)
	}
	if done := (chatMessage{Role: "assistant", Content: "Fini", State: "complete"}).display(); done["thinking"] != false {
		t.Fatal("a finished reply still thinks")
	}
	b, _ := testBackend(t)
	events := &lockedBuffer{}
	b.mu.Lock()
	b.out = events
	b.mu.Unlock()
	b.send("openai", "tool please")
	waitChat(t, b, "openai", func(rows []chatMessage, running bool) bool { return !running && len(rows) == 2 })
	sawToolThinking, sawText := false, false
	for _, line := range strings.Split(strings.TrimSpace(events.String()), "\n") {
		var record struct {
			Data struct {
				Items []object `json:"items"`
			} `json:"data"`
		}
		json.Unmarshal([]byte(line), &record)
		for _, item := range record.Data.Items {
			text, _ := item["text"].(string)
			if item["thinking"] == true && strings.Contains(text, "**bash**") {
				sawToolThinking = true
			}
			if item["thinking"] == false && strings.HasSuffix(text, "C'est fait.") {
				sawText = true
			}
		}
	}
	if !sawToolThinking || !sawText {
		t.Fatalf("thinking did not follow the tool call and the text:\n%s", events.String())
	}
}

// The backend writes events from several goroutines.
type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *lockedBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}
func (l *lockedBuffer) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

// Each conversation keeps its own thinking level: pi starts with it, a running
// pi receives a change at once, and the choice survives a restart.
func TestThinkingLevelsPerConversation(t *testing.T) {
	b, logFile := testBackend(t)
	status := func(key string) object {
		result, err := b.handle(b.ctx, "status", parameters{Conversation: key})
		if err != nil {
			t.Fatal(err)
		}
		return result.(object)
	}
	if level := status("qwen")["thinkingLevel"]; level != "off" {
		t.Fatalf("Qwen should start without thinking, got %v", level)
	}
	if level := status("openai")["thinkingLevel"]; level != "medium" {
		t.Fatalf("OpenAI should start at medium, got %v", level)
	}
	if _, err := b.handle(b.ctx, "setThinking", parameters{Conversation: "qwen", Level: "medium"}); err == nil {
		t.Fatal("Qwen only offers off and high")
	}
	if _, err := b.handle(b.ctx, "setThinking", parameters{Conversation: "openai", Level: "max"}); err == nil {
		t.Fatal("OpenAI stops at xhigh")
	}
	if _, err := b.handle(b.ctx, "setThinking", parameters{Conversation: "qwen", Level: "high"}); err != nil {
		t.Fatal(err)
	}
	if _, err := b.handle(b.ctx, "send", parameters{Conversation: "qwen", Text: "Salut"}); err != nil {
		t.Fatal(err)
	}
	waitChat(t, b, "qwen", func(rows []chatMessage, running bool) bool { return !running && len(rows) == 2 })
	if _, err := b.handle(b.ctx, "setThinking", parameters{Conversation: "qwen", Level: "off"}); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		args, commands := piLog(t, logFile)
		if len(args) == 1 && argValue(args[0], "--thinking") != "high" {
			t.Fatalf("pi did not start at the chosen level: %v", args[0])
		}
		found := false
		for _, command := range commands {
			found = found || command["type"] == "set_thinking_level" && command["level"] == "off"
		}
		if found {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("the running pi never received the new level: %v", commands)
		}
		time.Sleep(20 * time.Millisecond)
	}
	restarted, err := newBackend(b.ctx, io.Discard, b.stateDir)
	if err != nil {
		t.Fatal(err)
	}
	if level := restarted.thinkingLevelLocked("qwen"); level != "off" {
		t.Fatalf("the level was not saved, got %q", level)
	}
}
