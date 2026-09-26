package main

import (
	"context"
	"encoding/json"
	"fmt"
	"html"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	beeper "github.com/beeper/desktop-api-go/v5"
	"github.com/godbus/dbus/v5"
	"github.com/gorilla/websocket"
)

type event struct {
	Type    string   `json:"type"`
	Seq     int64    `json:"seq"`
	ChatID  string   `json:"chatID"`
	IDs     []string `json:"ids"`
	Entries []object `json:"entries"`
}

func textField(m object, key string) string { v, _ := m[key].(string); return v }
func boolField(m object, key string) bool   { v, _ := m[key].(bool); return v }
func mapField(m object, key string) object  { v, _ := m[key].(map[string]any); return v }
func dateField(m object, key string) time.Time {
	t, _ := time.Parse(time.RFC3339Nano, textField(m, key))
	return t
}
func (b *backend) runStream(ctx context.Context, c *beeper.Client, token string) {
	backoff := time.Second
	first := true
	lastConnected := time.Now()
	for ctx.Err() == nil {
		var accounts json.RawMessage
		probeCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		err := c.Get(probeCtx, "v1/accounts", nil, &accounts)
		cancel()
		if err == nil {
			u, _ := url.Parse(b.baseURL)
			if u.Scheme == "https" {
				u.Scheme = "wss"
			} else {
				u.Scheme = "ws"
			}
			u.Path = strings.TrimRight(u.Path, "/") + "/v1/ws"
			conn, response, dialErr := (&websocket.Dialer{HandshakeTimeout: 10 * time.Second}).DialContext(ctx, u.String(), http.Header{"Authorization": []string{"Bearer " + token}})
			err = dialErr
			if dialErr != nil && response != nil {
				if response.Body != nil {
					response.Body.Close()
				}
				if response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden {
					err = fail("unauthorized", "Beeper rejected access with the saved token.")
				}
			}
			if err == nil {
				connectedAt := time.Now()
				conn.SetReadLimit(8 * 1024 * 1024)
				_ = conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
				err = conn.WriteJSON(object{"type": "subscriptions.set", "requestID": "quickshell", "chatIDs": []string{"*"}})
				if err == nil {
					if syncErr := b.resync(ctx, c, !first, lastConnected); syncErr != nil {
						b.emit("warning", object{"message": "Synchronization failed. Updates will be retried."})
					}
					if ctx.Err() == nil {
						b.statusForContext(ctx, "connected", "Connected to Beeper")
					}
					first = false
					backoff = time.Second
					lastConnected = connectedAt
					b.resumePending(ctx)
					err = b.consume(ctx, conn, connectedAt)
				}
				conn.Close()
			}
		}
		if ctx.Err() != nil {
			return
		}
		if err != nil && safeError(err).Code == "unauthorized" {
			b.statusForContext(ctx, "invalid-token", "Beeper rejected the saved token. Check the approved connection in Beeper.")
		} else {
			b.statusForContext(ctx, "offline", "Beeper is unavailable. Reconnecting automatically with your saved token…")
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		if backoff < 30*time.Second {
			backoff *= 2
			if backoff > 30*time.Second {
				backoff = 30 * time.Second
			}
		}
	}
}
func (b *backend) consume(ctx context.Context, conn *websocket.Conn, since time.Time) error {
	stop := make(chan struct{})
	defer close(stop)
	_ = conn.SetReadDeadline(time.Now().Add(75 * time.Second))
	conn.SetPongHandler(func(string) error { return conn.SetReadDeadline(time.Now().Add(75 * time.Second)) })
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				conn.Close()
				return
			case <-stop:
				return
			case <-ticker.C:
				if err := conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(5*time.Second)); err != nil {
					conn.Close()
					return
				}
			}
		}
	}()
	var seq int64
	for {
		var e event
		if err := conn.ReadJSON(&e); err != nil {
			return err
		}
		if e.Type == "error" {
			return fmt.Errorf("subscription rejected")
		}
		if e.Seq > 0 {
			if seq > 0 && e.Seq != seq+1 {
				if c, err := b.api(); err == nil {
					_ = b.resync(ctx, c, true, since)
				}
			}
			seq = e.Seq
		}
		switch e.Type {
		case "chat.upserted", "chat.deleted":
			if e.Type == "chat.deleted" {
				ids := e.IDs
				if len(ids) == 0 && e.ChatID != "" {
					ids = []string{e.ChatID}
				}
				b.emit("chatsDeleted", object{"ids": ids})
			}
			b.emit("chatsChanged", object{})
		case "message.upserted", "message.deleted":
			if e.Type == "message.deleted" {
				b.emit("messagesDeleted", object{"chatID": e.ChatID, "ids": e.IDs})
			}
			b.emit("messagesChanged", object{"chatID": e.ChatID})
			b.emit("chatsChanged", object{})
			if e.Type == "message.upserted" {
				hydrated := map[string]bool{}
				for _, m := range e.Entries {
					hydrated[textField(m, "id")] = true
					b.considerMessage(ctx, e.ChatID, m, since)
				}
				for _, id := range e.IDs {
					if hydrated[id] {
						continue
					}
					fetchCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
					raw, err := b.raw(fetchCtx, "GET", messagePath(e.ChatID, id), nil)
					cancel()
					var m object
					if err == nil && json.Unmarshal(raw, &m) == nil {
						b.considerMessage(ctx, e.ChatID, m, since)
					}
				}
			}
		}
	}
}
func (b *backend) resync(ctx context.Context, c *beeper.Client, summary bool, since time.Time) error {
	cursor := ""
	chats := 0
	messages := 0
	seenCursors := map[string]bool{}
	for {
		p := parameters{Cursor: cursor, Direction: "before"}
		var page struct {
			Items        []object `json:"items"`
			HasMore      bool     `json:"hasMore"`
			OldestCursor string   `json:"oldestCursor"`
		}
		if err := c.Get(ctx, "v1/chats"+pageQuery(p), nil, &page); err != nil {
			return err
		}
		b.mu.Lock()
		for _, chat := range page.Items {
			m := mapField(chat, "preview")
			id := textField(m, "id")
			_, alreadySeen := b.state.Seen[textField(chat, "id")+"\x00"+id]
			if id != "" {
				b.state.Seen[textField(chat, "id")+"\x00"+id] = time.Now().Unix()
			}
			if summary && !alreadySeen && dateField(m, "timestamp").After(since) && !boolField(m, "isSender") && !muted(chat) && !boolField(m, "isDeleted") {
				if n, ok := chat["unreadCount"].(float64); ok && n > 0 {
					chats++
					messages += int(n)
				}
			}
		}
		b.state.LastSync = time.Now()
		err := b.persistLocked()
		b.mu.Unlock()
		if err != nil {
			return err
		}
		if !page.HasMore || page.OldestCursor == "" || seenCursors[page.OldestCursor] {
			break
		}
		cursor = page.OldestCursor
		seenCursors[cursor] = true
	}
	if summary && chats > 0 && b.notifications != nil {
		b.notifications.send("Messages received while disconnected", fmt.Sprintf("%d unread message(s) in %d conversation(s)", messages, chats), "", object{}, true)
	}
	b.emit("chatsChanged", object{})
	b.mu.Lock()
	chatID := b.view.ChatID
	b.mu.Unlock()
	if chatID != "" {
		b.emit("messagesChanged", object{"chatID": chatID})
	}
	return nil
}
func muted(chat object) bool {
	if boolField(chat, "isMuted") {
		return true
	}
	return dateField(mapField(chat, "snooze"), "snoozeUntil").After(time.Now())
}
func notificationCandidate(m object, since time.Time) bool {
	if textField(m, "id") == "" || boolField(m, "isSender") || boolField(m, "isDeleted") || boolField(m, "isHidden") || !dateField(m, "editedTimestamp").IsZero() {
		return false
	}
	if v, ok := m["isUnread"].(bool); ok && !v {
		return false
	}
	if !dateField(m, "timestamp").After(since) {
		return false
	}
	switch textField(m, "type") {
	case "REACTION", "NOTICE":
		return false
	}
	return true
}
func (b *backend) considerMessage(ctx context.Context, chatID string, m object, since time.Time) {
	id := textField(m, "id")
	if id == "" {
		return
	}
	key := chatID + "\x00" + id
	b.mu.Lock()
	_, seen := b.state.Seen[key]
	b.state.Seen[key] = time.Now().Unix()
	err := b.persistLocked()
	b.mu.Unlock()
	// The shell suppresses chat banners while open but still plays the sound,
	// including for the focused conversation. Do not discard that arrival here.
	if seen || err != nil || !notificationCandidate(m, since) || b.notifications == nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	raw, err := b.raw(ctx, "GET", chatPath(chatID), nil)
	if err != nil {
		return
	}
	var chat object
	if json.Unmarshal(raw, &chat) != nil || muted(chat) {
		return
	}
	name := textField(m, "senderName")
	title := textField(chat, "title")
	if name != "" && name != title {
		title = name + " · " + title
	}
	if title == "" {
		title = "New message"
	}
	body := plainText(textField(m, "text"))
	if body == "" {
		switch textField(m, "type") {
		case "IMAGE":
			body = "Image"
		case "VOICE":
			body = "Voice message"
		case "VIDEO":
			body = "Video"
		case "STICKER":
			body = "Sticker"
		default:
			body = "Attachment"
		}
	}
	if r := []rune(body); len(r) > 240 {
		body = string(r[:240]) + "…"
	}
	b.notifications.send(title, body, textField(chat, "imgURL"), object{"chatID": chatID, "messageID": id}, false)
}
func (b *backend) resumePending(ctx context.Context) {
	b.mu.Lock()
	pending := make(map[string]string, len(b.state.Pending))
	for id, chat := range b.state.Pending {
		pending[id] = chat
	}
	b.mu.Unlock()
	for id, chat := range pending {
		go b.resolvePending(ctx, chat, id)
	}
}
func (b *backend) resolvePending(ctx context.Context, chat, id string) {
	b.mu.Lock()
	if b.pendingActive == nil {
		b.pendingActive = map[string]bool{}
	}
	if b.pendingActive[id] {
		b.mu.Unlock()
		return
	}
	b.pendingActive[id] = true
	b.mu.Unlock()
	defer func() { b.mu.Lock(); delete(b.pendingActive, id); b.mu.Unlock() }()
	for attempt := 0; attempt < 30; attempt++ {
		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
		cctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		r, err := b.raw(cctx, "GET", messagePath(chat, id), nil)
		cancel()
		if err != nil {
			continue
		}
		var m object
		if json.Unmarshal(r, &m) != nil {
			continue
		}
		status := textField(mapField(m, "sendStatus"), "status")
		b.emit("messagesChanged", object{"chatID": chat})
		if status == "PENDING" {
			continue
		}
		if status == "FAIL_RETRIABLE" || status == "FAIL_PERMANENT" {
			b.emit("sendFailed", object{"chatID": chat, "pendingMessageID": id, "message": textField(mapField(m, "sendStatus"), "message")})
		}
		if status == "SUCCESS" || strings.HasPrefix(status, "FAIL_") || (textField(m, "id") != "" && textField(m, "id") != id) {
			b.mu.Lock()
			delete(b.state.Pending, id)
			_ = b.persistLocked()
			b.mu.Unlock()
			b.emit("pendingResolved", object{"chatID": chat, "pendingMessageID": id, "message": m})
			return
		}
	}
}

type notificationSink interface {
	send(title, body, icon string, target object, silent bool)
	close()
}
type notifier struct {
	conn    *dbus.Conn
	mu      sync.Mutex
	targets map[uint32]object
	emit    func(string, any)
}

func newNotifier(ctx context.Context, emit func(string, any)) (*notifier, error) {
	c, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil, err
	}
	n := &notifier{conn: c, targets: map[uint32]object{}, emit: emit}
	if err = c.AddMatchSignal(dbus.WithMatchInterface("org.freedesktop.Notifications"), dbus.WithMatchSender("org.freedesktop.Notifications")); err != nil {
		c.Close()
		return nil, err
	}
	signals := make(chan *dbus.Signal, 32)
	c.Signal(signals)
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case s, ok := <-signals:
				if !ok {
					return
				}
				if s == nil || len(s.Body) < 1 {
					continue
				}
				id, ok := s.Body[0].(uint32)
				if !ok {
					continue
				}
				n.mu.Lock()
				target := n.targets[id]
				if strings.HasSuffix(s.Name, "NotificationClosed") {
					delete(n.targets, id)
				}
				n.mu.Unlock()
				if strings.HasSuffix(s.Name, "ActionInvoked") && len(s.Body) > 1 && s.Body[1] == "default" && target != nil {
					emit("openChat", target)
				}
			}
		}
	}()
	return n, nil
}
func (n *notifier) close() { _ = n.conn.Close() }
func (n *notifier) send(title, body, icon string, target object, silent bool) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	hints := map[string]dbus.Variant{"desktop-entry": dbus.MakeVariant("quickshell-beeper"), "category": dbus.MakeVariant("im.received"), "suppress-sound": dbus.MakeVariant(silent)}
	var id uint32
	server := n.conn.Object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
	var capabilities []string
	if server.CallWithContext(ctx, "org.freedesktop.Notifications.GetCapabilities", 0).Store(&capabilities) == nil {
		for _, capability := range capabilities {
			if capability == "body-markup" {
				body = html.EscapeString(body)
				break
			}
		}
	}
	// Quickshell advertises plain text: entities would otherwise be visible in
	// ordinary messages such as "L'atelier & le café".
	err := server.CallWithContext(ctx, "org.freedesktop.Notifications.Notify", 0, "Messages", uint32(0), icon, title, body, []string{"default", "Open"}, hints, int32(-1)).Store(&id)
	if err != nil {
		n.emit("warning", object{"message": "Could not display the notification."})
		return
	}
	n.mu.Lock()
	n.targets[id] = target
	n.mu.Unlock()
}
