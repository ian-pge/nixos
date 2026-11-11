package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const localChatID = "local:qwen"
const localModel = "qwen3.5:4b-q4_K_M"

type localMessage struct {
	ID        string `json:"id"`
	Role      string `json:"role"`
	Content   string `json:"content"`
	Timestamp string `json:"timestamp"`
	State     string `json:"state,omitempty"`
}

// Only explicit local conversation messages are ever included in an Ollama request.
// Neither Beeper history, attachments nor credentials enter this transport.
func (m localMessage) display() object {
	text := m.Content
	if m.Role == "assistant" {
		if text == "" && m.State == "generating" {
			text = "…"
		}
		if m.State == "failed" {
			text += "\n\nCould not finish the reply. Check that Ollama is running and Qwen is installed."
		}
		if m.State == "interrupted" {
			text += "\n\nReply interrupted."
		}
		if m.State == "stopped" && text == "" {
			text = "Reply stopped."
		}
	}
	name := "Qwen"
	if m.Role == "user" {
		name = "You"
	}
	result := object{"id": m.ID, "chatID": localChatID, "senderID": m.Role,
		"senderName": name, "isSender": m.Role == "user", "timestamp": m.Timestamp,
		"text": html.EscapeString(text), "plainText": text, "type": "TEXT",
		"localState": m.State, "attachments": []object{}, "reactions": []object{}}
	if m.Role == "assistant" {
		result["markdownHTML"] = renderMarkdown(text)
	}
	return result
}

func (b *backend) localSnapshotLocked() object {
	snapshot := b.localMetadataLocked()
	rows := b.state.LocalMessages
	start := max(0, len(rows)-50)
	items := make([]object, 0, len(rows)-start)
	for _, m := range rows[start:] {
		items = append(items, m.display())
	}
	snapshot["items"] = items
	return snapshot
}

func (b *backend) localMetadataLocked() object {
	rows := b.state.LocalMessages
	var preview any = "Chat with Qwen on this computer"
	activity := ""
	if len(rows) > 0 {
		preview = rows[len(rows)-1].display()
		activity = rows[len(rows)-1].Timestamp
	}
	chat := object{"id": localChatID, "title": "Qwen local", "network": "ollama", "type": "single",
		"localAssistant": true, "isLowPriority": false, "unreadCount": 0, "preview": preview, "lastActivity": activity,
		"capabilities": object{"reply": false, "edit": false, "delete": false, "reaction": false},
		"participants": object{"items": []object{{"id": "assistant", "fullName": "Qwen", "isSelf": false}}, "total": 1, "hasMore": false}}
	return object{"chat": chat, "revision": b.localRevision, "generating": b.localCancel != nil}
}

func (b *backend) handleLocal(_ context.Context, method string, p parameters) (any, error) {
	switch method {
	case "ollamaStatus":
		b.mu.Lock()
		defer b.mu.Unlock()
		return b.localSnapshotLocked(), nil
	case "ollamaCancel":
		b.mu.Lock()
		defer b.mu.Unlock()
		if b.localCancel != nil {
			b.localCancel()
		}
		return object{}, nil
	case "send":
		return b.sendLocal(p)
	case "messages", "message", "search":
		b.mu.Lock()
		defer b.mu.Unlock()
		rows := b.state.LocalMessages
		if method == "message" {
			for _, m := range rows {
				if m.ID == p.MessageID {
					return m.display(), nil
				}
			}
			return nil, fail("not_found", "Message not found.")
		}
		items := []object{}
		if method == "search" {
			for _, m := range rows {
				if strings.Contains(strings.ToLower(m.Content), strings.ToLower(p.Query)) {
					items = append(items, m.display())
				}
			}
			return demoPage(items), nil
		}
		end := len(rows)
		if p.Cursor != "" {
			n, err := strconv.Atoi(p.Cursor)
			if err != nil || n < 0 || n > end {
				return nil, fail("invalid_params", "Invalid local history cursor.")
			}
			end = n
		}
		start := max(0, end-50)
		for _, m := range rows[start:end] {
			items = append(items, m.display())
		}
		return object{"items": items, "hasMore": start > 0, "oldestCursor": strconv.Itoa(start), "revision": b.localRevision}, nil
	default:
		return nil, fail("unsupported", "This action is unavailable in the local AI conversation.")
	}
}

func (b *backend) sendLocal(p parameters) (any, error) {
	if strings.TrimSpace(p.Text) == "" || len(p.Text) > 16000 {
		return nil, fail("invalid_params", "Enter a message shorter than 16 KB.")
	}
	if p.Attachment != nil || len(p.Attachments) != 0 || p.ReplyToMessageID != "" {
		return nil, fail("unsupported", "Qwen currently accepts text messages only.")
	}
	b.mu.Lock()
	if b.localCancel != nil {
		b.mu.Unlock()
		return nil, fail("busy", "Wait for Qwen's reply or stop it first.")
	}
	now := time.Now()
	user := localMessage{ID: fmt.Sprintf("qwen-%d-user", now.UnixNano()), Role: "user", Content: p.Text, Timestamp: now.Format(time.RFC3339Nano)}
	assistant := localMessage{ID: fmt.Sprintf("qwen-%d-assistant", now.UnixNano()), Role: "assistant", Timestamp: now.Add(time.Nanosecond).Format(time.RFC3339Nano), State: "generating"}
	before := b.state.LocalMessages
	b.state.LocalMessages = append(append([]localMessage{}, before...), user, assistant)
	if err := b.persistLocked(); err != nil {
		b.state.LocalMessages = before
		b.mu.Unlock()
		return nil, fail("storage", "Could not save the local conversation.")
	}
	// Bound the model context; the complete visible history remains on disk.
	contextMessages := []object{{"role": "system", "content": "You are Qwen, a helpful assistant running locally on the user's computer. Respond in the user's language. Be clear and concise. You have no access to their other conversations or applications and cannot perform actions on their computer."}}
	selected := []localMessage{}
	budget := 24000
	for i := len(b.state.LocalMessages) - 2; i >= 0 && len(selected) < 24; i-- {
		m := b.state.LocalMessages[i]
		if m.Role == "assistant" && m.State != "complete" {
			continue
		}
		if len(m.Content) > budget {
			break
		}
		budget -= len(m.Content)
		selected = append(selected, m)
	}
	for i := len(selected) - 1; i >= 0; i-- {
		m := selected[i]
		if len(contextMessages) == 1 && m.Role != "user" {
			continue
		}
		contextMessages = append(contextMessages, object{"role": m.Role, "content": m.Content})
	}
	ctx, cancel := context.WithTimeout(b.ctx, 5*time.Minute)
	b.localCancel = cancel
	b.localRevision++
	snapshot := b.localSnapshotLocked()
	b.mu.Unlock()
	b.emit("ollamaChanged", snapshot)
	go b.generateLocal(ctx, cancel, assistant.ID, contextMessages)
	return object{"chatID": localChatID, "messageID": user.ID}, nil
}

func (b *backend) updateLocalReply(id, content, state string, final bool) {
	b.mu.Lock()
	var changed object
	for i := range b.state.LocalMessages {
		if b.state.LocalMessages[i].ID == id {
			b.state.LocalMessages[i].Content = content
			b.state.LocalMessages[i].State = state
			changed = b.state.LocalMessages[i].display()
			break
		}
	}
	if final {
		b.localCancel = nil
	}
	b.localRevision++
	var persistErr error
	if final {
		persistErr = b.persistLocked()
	}
	snapshot := b.localMetadataLocked()
	// Stream only the changing bubble; older delegates keep their snapshots.
	snapshot["items"] = []object{changed}
	b.mu.Unlock()
	b.emit("ollamaChanged", snapshot)
	if persistErr != nil {
		b.emit("warning", object{"message": "Could not save Qwen's reply to disk."})
	}
}

func (b *backend) generateLocal(ctx context.Context, cancel context.CancelFunc, id string, messages []object) {
	defer cancel()
	content, state := "", "failed"
	defer func() {
		if errors.Is(ctx.Err(), context.Canceled) {
			state = "stopped"
		}
		b.updateLocalReply(id, content, state, true)
	}()
	body, _ := json.Marshal(object{"model": localModel, "messages": messages, "stream": true, "think": false,
		"keep_alive": "10m", "options": object{"num_ctx": 8192, "num_predict": 2048, "temperature": 0.7}})
	req, err := http.NewRequestWithContext(ctx, "POST", b.localURL, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	transport := &http.Transport{DialContext: (&net.Dialer{Timeout: 5 * time.Second}).DialContext}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(req)
	if err != nil {
		return
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return
	}
	scanner := bufio.NewScanner(io.LimitReader(response.Body, 8*1024*1024))
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	last := time.Time{}
	for scanner.Scan() {
		var chunk struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
			Done  bool   `json:"done"`
			Error string `json:"error"`
		}
		if json.Unmarshal(scanner.Bytes(), &chunk) != nil || chunk.Error != "" {
			return
		}
		content += chunk.Message.Content
		if len(content) > 128*1024 {
			return
		}
		if chunk.Done {
			if strings.TrimSpace(content) != "" {
				state = "complete"
			}
			return
		}
		if time.Since(last) >= 50*time.Millisecond {
			b.updateLocalReply(id, content, "generating", false)
			last = time.Now()
		}
	}
}
