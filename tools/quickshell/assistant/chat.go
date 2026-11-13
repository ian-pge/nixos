package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode"
)

// The local model, served by Ollama (system/ollama.nix). Correction and GPU
// unloading talk to Ollama directly; conversations go through pi.
const model = "huihui_ai/qwen3.5-abliterated:9b"
const pageSize = 50

type conversationSpec struct {
	Key, Model, Tools, Prompt string
	Local                     bool
	// Told where the user's screenshots are, to look at them when asked.
	Screenshots bool
	// Thinking levels offered in the chat, from the lowest; the first of
	// DefaultThinking applies until the user picks another.
	ThinkingLevels  []string
	DefaultThinking string
}

// Qwen is always read-only. OpenAI may act on the whole computer with the
// user's own permissions: pi does not ask before each tool call.
var conversationKeys = []string{"qwen", "openai"}
var specs = map[string]conversationSpec{
	"qwen": {Key: "qwen", Model: "ollama/" + model, Tools: "read,grep,find,ls", Local: true,
		ThinkingLevels: []string{"off", "high"}, DefaultThinking: "off",
		Prompt: "You are Qwen, running locally in the user's Quickshell desktop chat. Your working directory is the file system root (/), and the user's home is $HOME. You can read files anywhere and list or search the file system, but you cannot modify anything or run commands. Respond in the user's language, clearly and concisely."},
	"openai": {Key: "openai", Model: "openai-codex/gpt-6.1-sol", Tools: "read,bash,edit,write,grep,find,ls",
		ThinkingLevels: []string{"low", "medium", "high", "xhigh"}, DefaultThinking: "medium", Screenshots: true,
		Prompt: "You are running in the user's Quickshell desktop chat on their NixOS computer, with full access through your tools. Your working directory is the file system root (/), and the user's home is $HOME. Respond in the user's language, clearly and concisely."},
}

type chatMessage struct {
	ID        string `json:"id"`
	Role      string `json:"role"`
	Content   string `json:"content"`
	Timestamp string `json:"timestamp"`
	State     string `json:"state,omitempty"`
}

func (m chatMessage) displayText() string {
	text := m.Content
	if m.Role == "assistant" {
		if text == "" && m.State == "generating" {
			text = "…"
		}
		if m.State == "failed" {
			text += "\n\nCould not finish the reply."
		}
		if m.State == "interrupted" {
			text += "\n\nReply interrupted."
		}
		if m.State == "stopped" && text == "" {
			text = "Reply stopped."
		}
	}
	return strings.TrimLeft(text, "\n")
}

func (m chatMessage) display() object {
	text := m.displayText()
	// The QML view renders one HTML format: Goldmark output for replies and
	// escaped literal text for the user's own messages.
	rendered := renderMarkdown(text)
	if m.Role != "assistant" {
		rendered = `<p style="white-space:pre-wrap">` + strings.ReplaceAll(html.EscapeString(text), "\n", "<br/>") + `</p>`
	}
	// Thinking: the agent works but no reply text is streaming yet. The live
	// run refines this between messages and during tool calls.
	return object{"id": m.ID, "role": m.Role, "isSender": m.Role == "user", "timestamp": m.Timestamp,
		"text": text, "html": rendered, "state": m.State,
		"thinking": m.Role == "assistant" && m.State == "generating" && strings.TrimSpace(m.Content) == ""}
}

func conversationKey(key string) (string, error) {
	if key == "" {
		return "qwen", nil
	}
	if _, ok := specs[key]; !ok {
		return "", fail("invalid_params", "Unknown conversation.")
	}
	return key, nil
}

func (b *backend) runtime(key string) *conversationRuntime {
	r := b.runtimes[key]
	if r == nil {
		r = &conversationRuntime{}
		b.runtimes[key] = r
	}
	return r
}

func (b *backend) metadataLocked(key string) object {
	r := b.runtime(key)
	return object{"conversation": key, "revision": b.revision, "resetRevision": r.resetRevision,
		"generating": r.run != nil, "unloading": specs[key].Local && b.unloading,
		"thinkingLevel": b.thinkingLevelLocked(key), "thinkingLevels": specs[key].ThinkingLevels}
}

func (b *backend) snapshotLocked(key string) object {
	snapshot := b.metadataLocked(key)
	page, _ := b.pageLocked(key, "")
	for k, value := range page.(object) {
		snapshot[k] = value
	}
	snapshot["draft"] = b.state.Conversations[key].Draft
	return snapshot
}

// Opaque decimal cursors index the persisted history; they are never shown.
func (b *backend) pageLocked(key, cursor string) (any, error) {
	rows := b.state.Conversations[key].Messages
	end := len(rows)
	if cursor != "" {
		n, err := strconv.Atoi(cursor)
		if err != nil || n < 0 || n > end {
			return nil, fail("invalid_params", "Invalid history cursor.")
		}
		end = n
	}
	start := max(0, end-pageSize)
	items := make([]object, 0, end-start)
	for _, m := range rows[start:end] {
		items = append(items, m.display())
	}
	return object{"conversation": key, "items": items, "hasMore": start > 0, "oldestCursor": strconv.Itoa(start),
		"revision": b.revision, "resetRevision": b.runtime(key).resetRevision}, nil
}

// Case- and accent-insensitive: every word of the query must appear.
func searchFold(value string) string {
	var out strings.Builder
	for _, r := range strings.ToLower(value) {
		if folded, ok := accentFold[r]; ok {
			out.WriteString(folded)
		} else if !unicode.Is(unicode.Mn, r) {
			out.WriteRune(r)
		}
	}
	return out.String()
}

var accentFold = func() map[rune]string {
	table := map[rune]string{'æ': "ae", 'œ': "oe", 'ß': "ss"}
	for base, letters := range map[string]string{"a": "àáâãäåā", "c": "çćč", "e": "èéêëēė", "i": "ìíîïī", "n": "ñń", "o": "òóôõöøō", "u": "ùúûüū", "y": "ýÿ"} {
		for _, r := range letters {
			table[r] = base
		}
	}
	return table
}()

func (b *backend) searchLocked(key, query string) object {
	words := strings.Fields(searchFold(query))
	ids := []string{}
	if len(words) == 0 {
		return object{"ids": ids}
	}
	for _, m := range b.state.Conversations[key].Messages {
		text := searchFold(m.displayText())
		found := true
		for _, word := range words {
			if !strings.Contains(text, word) {
				found = false
				break
			}
		}
		if found {
			ids = append(ids, m.ID)
		}
	}
	return object{"ids": ids}
}

// Reset clears the displayed history and starts a new pi session, so the
// model context is empty too. The unsent draft is kept.
func (b *backend) reset(key string) (any, error) {
	b.mu.Lock()
	if specs[key].Local && b.unloading {
		b.mu.Unlock()
		return nil, fail("busy", "Wait for Qwen to finish unloading.")
	}
	c := b.state.Conversations[key]
	before, session := c.Messages, c.SessionID
	c.Messages, c.SessionID = []chatMessage{}, newSessionID()
	if err := b.persistLocked(); err != nil {
		c.Messages, c.SessionID = before, session
		b.mu.Unlock()
		return nil, fail("storage", "Could not reset the conversation.")
	}
	r := b.runtime(key)
	agent := r.agent
	r.agent, r.run = nil, nil
	b.revision++
	r.resetRevision = b.revision
	snapshot := b.snapshotLocked(key)
	b.mu.Unlock()
	// Never hold the ordered control loop while pi shuts down.
	if agent != nil {
		go agent.stop()
	}
	b.emit("changed", snapshot)
	return snapshot, nil
}

func localClient() (*http.Client, *http.Transport) {
	// No proxy from the environment and no redirects: the request stays local.
	transport := &http.Transport{DialContext: (&net.Dialer{Timeout: 5 * time.Second}).DialContext}
	return &http.Client{Transport: transport, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}, transport
}

// Only the local model occupies the GPU. A running reply is stopped first so
// it cannot reload the model after the unload request.
func (b *backend) unload(ctx context.Context) (any, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	b.mu.Lock()
	if b.unloading {
		b.mu.Unlock()
		return nil, fail("busy", "Qwen is already unloading.")
	}
	b.unloading = true
	r := b.runtime("qwen")
	var done chan struct{}
	if r.run != nil {
		done = r.run.done
		if r.agent != nil {
			r.agent.send(object{"type": "abort"})
		}
	}
	b.revision++
	snapshot := b.metadataLocked("qwen")
	b.mu.Unlock()
	b.emit("changed", snapshot)
	defer func() {
		b.mu.Lock()
		b.unloading = false
		b.revision++
		snapshot := b.metadataLocked("qwen")
		b.mu.Unlock()
		b.emit("changed", snapshot)
	}()
	if done != nil {
		select {
		case <-done:
		case <-ctx.Done():
			return nil, fail("ollama", "Could not stop Qwen's reply before unloading.")
		}
	}
	body, _ := json.Marshal(object{"model": model, "messages": []object{}, "stream": false, "keep_alive": 0})
	req, err := http.NewRequestWithContext(ctx, "POST", b.chatURL, bytes.NewReader(body))
	if err != nil {
		return nil, fail("ollama", "Could not unload Qwen. Check that Ollama is running.")
	}
	req.Header.Set("Content-Type", "application/json")
	client, transport := localClient()
	defer transport.CloseIdleConnections()
	response, err := client.Do(req)
	if err != nil {
		return nil, fail("ollama", "Could not unload Qwen. Check that Ollama is running.")
	}
	defer response.Body.Close()
	var result struct {
		Done       bool   `json:"done"`
		DoneReason string `json:"done_reason"`
		Error      string `json:"error"`
	}
	if response.StatusCode != http.StatusOK || json.NewDecoder(io.LimitReader(response.Body, 1024*1024)).Decode(&result) != nil || !result.Done || result.DoneReason != "unload" || result.Error != "" {
		return nil, fail("ollama", "Ollama could not confirm that Qwen was unloaded.")
	}
	return object{"unloaded": true}, nil
}

func (b *backend) send(key, text string) (any, error) {
	if strings.TrimSpace(text) == "" || len(text) > 16000 {
		return nil, fail("invalid_params", "Enter a message shorter than 16 KB.")
	}
	b.mu.Lock()
	r := b.runtime(key)
	if r.run != nil || specs[key].Local && b.unloading {
		b.mu.Unlock()
		return nil, fail("busy", "Wait for the current reply to finish.")
	}
	c := b.state.Conversations[key]
	now := time.Now()
	user := chatMessage{ID: fmt.Sprintf("%s-%d-user", key, now.UnixNano()), Role: "user", Content: text, Timestamp: now.Format(time.RFC3339Nano)}
	assistant := chatMessage{ID: fmt.Sprintf("%s-%d-assistant", key, now.UnixNano()), Role: "assistant", Timestamp: now.Add(time.Millisecond).Format(time.RFC3339Nano), State: "generating"}
	before := c.Messages
	c.Messages = append(append([]chatMessage{}, before...), user, assistant)
	if err := b.persistLocked(); err != nil {
		c.Messages = before
		b.mu.Unlock()
		return nil, fail("storage", "Could not save the conversation.")
	}
	run := &agentRun{replyID: assistant.ID, done: make(chan struct{})}
	r.run = run
	b.revision++
	snapshot := b.snapshotLocked(key)
	agent := r.agent
	if agent == nil {
		var err error
		if agent, err = b.startAgent(key, c.SessionID); err != nil {
			b.mu.Unlock()
			b.emit("changed", snapshot)
			b.finishRun(key, run, "failed", "Could not start pi: "+err.Error())
			return object{"messageID": user.ID}, nil
		}
		r.agent = agent
	}
	b.mu.Unlock()
	b.emit("changed", snapshot)
	if err := agent.send(object{"id": "prompt-" + user.ID, "type": "prompt", "message": text}); err != nil {
		b.finishRun(key, run, "failed", "Could not reach pi.")
	}
	return object{"messageID": user.ID}, nil
}

func (b *backend) cancel(key string) {
	b.mu.Lock()
	r := b.runtime(key)
	agent, running := r.agent, r.run != nil
	b.mu.Unlock()
	if running && agent != nil {
		agent.send(object{"type": "abort"})
	}
}

func (b *backend) thinkingLevelLocked(key string) string {
	level := b.state.Conversations[key].Thinking
	if !slices.Contains(specs[key].ThinkingLevels, level) {
		return specs[key].DefaultThinking
	}
	return level
}

// The level is saved with the conversation and given to a running pi at once:
// it applies from the next model request, even within a running reply.
func (b *backend) setThinking(key, level string) (any, error) {
	if !slices.Contains(specs[key].ThinkingLevels, level) {
		return nil, fail("invalid_params", "Unknown thinking level for this model.")
	}
	b.mu.Lock()
	c := b.state.Conversations[key]
	before := c.Thinking
	c.Thinking = level
	if err := b.persistLocked(); err != nil {
		c.Thinking = before
		b.mu.Unlock()
		return nil, fail("storage", "Could not save the thinking level.")
	}
	agent := b.runtime(key).agent
	b.revision++
	snapshot := b.metadataLocked(key)
	b.mu.Unlock()
	if agent != nil {
		_ = agent.send(object{"type": "set_thinking_level", "level": level})
	}
	b.emit("changed", snapshot)
	return snapshot, nil
}
