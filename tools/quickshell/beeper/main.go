// quickshell-beeper bridges the public Beeper Desktop API to a QML client.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	beeper "github.com/beeper/desktop-api-go/v5"
	"github.com/beeper/desktop-api-go/v5/option"
)

type object = map[string]any
type request struct {
	ID     json.RawMessage `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params"`
}
type rpcError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e *rpcError) Error() string     { return e.Message }
func fail(code, message string) error { return &rpcError{code, message} }

type parameters struct {
	ChatID           string      `json:"chatID"`
	MessageID        string      `json:"messageID"`
	AccountID        string      `json:"accountID"`
	UserID           string      `json:"userID"`
	Text             string      `json:"text"`
	Query            string      `json:"query"`
	Cursor           string      `json:"cursor"`
	Direction        string      `json:"direction"`
	Token            string      `json:"token"`
	ReplyToMessageID string      `json:"replyToMessageID"`
	ReactionKey      string      `json:"reactionKey"`
	Remove           bool        `json:"remove"`
	Attachment       *attachment `json:"attachment"`
	Changes          object      `json:"changes"`
	Path             string      `json:"path"`
	Type             string      `json:"type"`
	URL              string      `json:"url"`
	Focused          bool        `json:"focused"`
	AtLatest         bool        `json:"atLatest"`
}
type backend struct {
	mu                   sync.Mutex
	writeMu              sync.Mutex
	out                  io.Writer
	ctx                  context.Context
	client               *beeper.Client
	baseURL              string
	token                string
	stateName            string
	stateMessage         string
	stateRevision        uint64
	credentials          credentialStore
	restoringCredentials bool
	credentialWake       chan struct{}
	credentialRetryDelay time.Duration
	state                *diskState
	stateDir             string
	demo                 bool
	demoChats            []object
	demoMessages         map[string][]object
	view                 parameters
	streamCancel         context.CancelFunc
	pendingActive        map[string]bool
	notifications        notificationSink
	started              time.Time
}

func main() {
	demo := flag.Bool("demo", false, "fictional in-memory conversations; never connects to Beeper")
	flag.Bool("stdio", true, "JSONL protocol on stdin/stdout (default)")
	flag.Parse()
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	stateDir := os.Getenv("XDG_STATE_HOME")
	if stateDir == "" {
		h, _ := os.UserHomeDir()
		stateDir = filepath.Join(h, ".local", "state")
	}
	b, err := newBackend(ctx, os.Stdout, filepath.Join(stateDir, "quickshell-beeper"), *demo)
	if err != nil {
		fmt.Fprintln(os.Stderr, "quickshell-beeper: cannot open private local state:", err)
		os.Exit(1)
	}
	if !*demo {
		b.notifications, err = newNotifier(ctx, b.emit)
		if err != nil {
			b.emit("warning", object{"message": "Notifications indisponibles : connexion D-Bus impossible."})
		}
		go b.initialize()
	} else {
		b.status("demo", "Démonstration · conversations fictives")
	}
	go func() { <-ctx.Done(); os.Stdin.Close() }()
	if err := b.serve(os.Stdin); err != nil {
		fmt.Fprintln(os.Stderr, "quickshell-beeper: invalid input stream")
	}
	cancel()
	if b.notifications != nil {
		b.notifications.close()
	}
}

func newBackend(ctx context.Context, out io.Writer, dir string, demo bool) (*backend, error) {
	b := &backend{ctx: ctx, out: out, stateDir: dir, demo: demo, started: time.Now(),
		stateName: "loading-token", stateMessage: "Récupération de l’accès enregistré…", stateRevision: 1,
		credentials: secretCredentialStore{}, credentialWake: make(chan struct{}, 1), credentialRetryDelay: 3 * time.Second,
		baseURL: "http://localhost:23373/"}
	if raw := os.Getenv("BEEPER_API_URL"); raw != "" {
		u, err := url.Parse(raw)
		if err != nil || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Scheme != "http" && u.Scheme != "https") || (u.Hostname() != "localhost" && u.Hostname() != "127.0.0.1" && u.Hostname() != "::1") {
			return nil, errors.New("BEEPER_API_URL must be a loopback HTTP URL")
		}
		b.baseURL = strings.TrimRight(raw, "/") + "/"
	}
	var err error
	b.state, err = loadState(dir, demo)
	if err != nil {
		return nil, err
	}
	if demo {
		b.initDemo()
		b.stateName = "demo"
	}
	return b, nil
}

func (b *backend) write(v any) {
	b.writeMu.Lock()
	defer b.writeMu.Unlock()
	_ = json.NewEncoder(b.out).Encode(v)
}
func (b *backend) emit(event string, data any) { b.write(object{"event": event, "data": data}) }
func (b *backend) serve(in io.Reader) error {
	var jobs sync.WaitGroup
	defer jobs.Wait()
	slots := make(chan struct{}, 8)
	respond := func(req request, p parameters) {
		ctx, cancel := context.WithTimeout(b.ctx, 90*time.Second)
		defer cancel()
		result, err := b.handle(ctx, req.Method, p)
		if err != nil {
			b.write(object{"id": req.ID, "error": safeError(err)})
		} else {
			b.write(object{"id": req.ID, "result": result})
		}
	}
	s := bufio.NewScanner(in)
	s.Buffer(make([]byte, 64*1024), 4*1024*1024)
	for s.Scan() {
		var req request
		if err := json.Unmarshal(s.Bytes(), &req); err != nil || len(req.ID) == 0 || req.Method == "" {
			b.write(object{"id": nil, "error": &rpcError{"invalid_request", "Requête JSONL invalide."}})
			continue
		}
		var p parameters
		if len(req.Params) > 0 && string(req.Params) != "null" {
			if err := json.Unmarshal(req.Params, &p); err != nil {
				b.write(object{"id": req.ID, "error": &rpcError{"invalid_params", "Paramètres invalides."}})
				continue
			}
		}
		// Preserve draft/control ordering while media and HTTP work cannot block focus updates.
		switch req.Method {
		case "status", "reconnect", "setView", "saveDraft", "getDraft", "discardAttachment":
			respond(req, p)
		default:
			if b.demo {
				respond(req, p)
				continue
			}
			select {
			case slots <- struct{}{}:
				jobs.Add(1)
				go func() { defer jobs.Done(); defer func() { <-slots }(); respond(req, p) }()
			default:
				b.write(object{"id": req.ID, "error": &rpcError{"busy", "Plusieurs actions sont en cours. Réessaie dans un instant."}})
			}
		}
	}
	return s.Err()
}

func safeError(err error) *rpcError {
	var r *rpcError
	if errors.As(err, &r) {
		return r
	}
	var api *beeper.Error
	if errors.As(err, &api) {
		switch api.StatusCode {
		case 401, 403:
			return &rpcError{"unauthorized", "Jeton refusé. Vérifie l’accès à l’API dans Beeper."}
		case 404:
			return &rpcError{"not_found", "Élément introuvable ou fonctionnalité indisponible dans cette version de Beeper."}
		case 400, 409, 422:
			return &rpcError{"unsupported", "Beeper a refusé cette action. Vérifie les capacités de la conversation et les paramètres."}
		case 429:
			return &rpcError{"rate_limit", "Trop de requêtes. Réessaie dans un instant."}
		}
		return &rpcError{"api_error", fmt.Sprintf("Beeper a répondu avec une erreur HTTP %d.", api.StatusCode)}
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return &rpcError{"timeout", "Beeper n’a pas répondu à temps."}
	}
	return &rpcError{"unavailable", "Action impossible. Vérifie que Beeper et son API locale sont lancés."}
}
func (b *backend) installClient(token string, replace bool) {
	c := apiClient(b.baseURL, token)
	b.mu.Lock()
	if b.client != nil && !replace {
		b.mu.Unlock()
		return
	}
	if b.streamCancel != nil {
		b.streamCancel()
	}
	b.client, b.token = &c, token
	ctx, cancel := context.WithCancel(b.ctx)
	b.streamCancel = cancel
	state := b.setStatusLocked("connecting", "Connexion à Beeper avec l’accès enregistré…")
	b.mu.Unlock()
	b.emit("status", state)
	b.wakeCredentials()
	go b.runStream(ctx, &c, token)
}
func apiClient(baseURL, token string) beeper.Client {
	return beeper.NewClient(option.WithBaseURL(baseURL), option.WithAccessToken(token), option.WithMaxRetries(0), option.WithHTTPClient(&http.Client{Timeout: 60 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}))
}
func (b *backend) api() (*beeper.Client, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.client == nil {
		return nil, fail("needs_token", "Ajoute ton jeton Beeper pour te connecter.")
	}
	return b.client, nil
}
func (b *backend) raw(ctx context.Context, method, path string, body any) (json.RawMessage, error) {
	c, err := b.api()
	if err != nil {
		return nil, err
	}
	var result json.RawMessage
	switch method {
	case "GET":
		err = c.Get(ctx, path, nil, &result)
	case "POST":
		err = c.Post(ctx, path, body, &result)
	case "PUT":
		err = c.Put(ctx, path, body, &result)
	case "PATCH":
		err = c.Patch(ctx, path, body, &result)
	case "DELETE":
		err = c.Delete(ctx, path, body, &result)
	}
	if len(result) == 0 {
		result = json.RawMessage(`{}`)
	}
	if method == "GET" {
		result = withPlainText(result)
	}
	return result, err
}
func chatPath(id string) string          { return "v1/chats/" + url.PathEscape(id) }
func messagePath(chat, id string) string { return chatPath(chat) + "/messages/" + url.PathEscape(id) }
func pageQuery(p parameters) string {
	q := url.Values{}
	if p.Cursor != "" {
		q.Set("cursor", p.Cursor)
	}
	if p.Direction != "" {
		q.Set("direction", p.Direction)
	}
	if len(q) > 0 {
		return "?" + q.Encode()
	}
	return ""
}
func (b *backend) handle(ctx context.Context, method string, p parameters) (any, error) {
	switch method {
	case "status":
		return b.statusSnapshot(), nil
	case "reconnect":
		if !b.demo {
			b.reconnect()
		}
		return b.statusSnapshot(), nil
	case "setView":
		b.mu.Lock()
		b.view = p
		b.mu.Unlock()
		return object{}, nil
	case "getDraft":
		b.mu.Lock()
		defer b.mu.Unlock()
		if d, ok := b.state.Drafts[p.ChatID]; ok {
			return d, nil
		}
		return draft{}, nil
	case "saveDraft":
		if p.ChatID == "" {
			return nil, fail("invalid_params", "Conversation manquante.")
		}
		b.mu.Lock()
		defer b.mu.Unlock()
		d := draft{Text: p.Text, Attachment: p.Attachment, ReplyToMessageID: p.ReplyToMessageID}
		b.state.Drafts[p.ChatID] = d
		return d, b.persistLocked()
	case "stageAttachment":
		return b.stage(p.Path, p.Type)
	case "clipboardAttachment":
		return b.clipboard(ctx)
	case "prepareRecording":
		return b.prepareRecording()
	case "discardAttachment":
		return object{}, b.discard(p.Path)
	}
	if b.demo {
		return b.handleDemo(method, p)
	}
	if method == "connect" {
		token := strings.TrimSpace(p.Token)
		if token == "" || strings.ContainsAny(token, "\r\n") {
			return nil, fail("invalid_token", "Le jeton est vide ou invalide.")
		}
		c := apiClient(b.baseURL, token)
		if _, err := c.Accounts.List(ctx); err != nil {
			return nil, err
		}
		if err := b.credentials.Store(ctx, token); err != nil {
			return nil, fail("keyring", "Le trousseau ne peut pas enregistrer le jeton. Déverrouille le trousseau GNOME.")
		}
		b.installClient(token, true)
		return b.statusSnapshot(), nil
	}
	if _, err := b.api(); err != nil {
		return nil, err
	}
	switch method {
	case "refresh":
		b.emit("chatsChanged", object{})
		b.mu.Lock()
		chat := b.view.ChatID
		b.mu.Unlock()
		if chat != "" {
			b.emit("messagesChanged", object{"chatID": chat})
		}
		return object{}, nil
	case "accounts":
		return b.raw(ctx, "GET", "v1/accounts", nil)
	case "chats":
		return b.raw(ctx, "GET", "v1/chats"+pageQuery(p), nil)
	case "contacts":
		if p.AccountID == "" {
			return nil, fail("invalid_params", "Compte manquant.")
		}
		return b.raw(ctx, "GET", "v1/accounts/"+url.PathEscape(p.AccountID)+"/contacts?query="+url.QueryEscape(p.Query), nil)
	case "search":
		q := url.Values{"query": {p.Query}}
		if p.ChatID != "" {
			q.Set("chatIDs", p.ChatID)
		}
		if p.Cursor != "" {
			q.Set("cursor", p.Cursor)
		}
		return b.raw(ctx, "GET", "v1/messages/search?"+q.Encode(), nil)
	case "download":
		if p.URL == "" {
			return nil, fail("invalid_params", "Adresse du média manquante.")
		}
		return b.raw(ctx, "POST", "v1/assets/download", object{"url": p.URL})
	case "upload":
		return b.upload(ctx, p.Path)
	case "startChat":
		if p.AccountID == "" || p.UserID == "" {
			return nil, fail("invalid_params", "Compte et contact requis.")
		}
		r, e := b.raw(ctx, "POST", "v1/chats/start", object{"accountID": p.AccountID, "user": object{"id": p.UserID}})
		if e == nil {
			b.emit("chatsChanged", object{})
		}
		return r, e
	}
	if p.ChatID == "" {
		return nil, fail("invalid_params", "Conversation manquante.")
	}
	switch method {
	case "messages":
		return b.raw(ctx, "GET", chatPath(p.ChatID)+"/messages"+pageQuery(p), nil)
	case "message":
		if p.MessageID == "" {
			return nil, fail("invalid_params", "Message manquant.")
		}
		return b.raw(ctx, "GET", messagePath(p.ChatID, p.MessageID), nil)
	case "send":
		return b.send(ctx, p)
	case "read":
		r, e := b.raw(ctx, "POST", chatPath(p.ChatID)+"/read", object{})
		if e == nil {
			b.emit("chatsChanged", object{})
		}
		return r, e
	case "updateChat":
		for key := range p.Changes {
			switch key {
			case "isMuted", "isPinned", "isArchived", "isLowPriority":
			default:
				return nil, fail("invalid_params", "Modification de conversation non prise en charge.")
			}
		}
		r, e := b.raw(ctx, "PATCH", chatPath(p.ChatID), p.Changes)
		if e == nil {
			b.emit("chatsChanged", object{})
		}
		return r, e
	case "edit", "delete", "react":
		if p.MessageID == "" {
			return nil, fail("invalid_params", "Message manquant.")
		}
		var r json.RawMessage
		var e error
		if method == "edit" {
			r, e = b.raw(ctx, "PUT", messagePath(p.ChatID, p.MessageID), object{"text": p.Text})
		}
		if method == "delete" {
			r, e = b.raw(ctx, "DELETE", messagePath(p.ChatID, p.MessageID), nil)
		}
		if method == "react" {
			if p.ReactionKey == "" {
				return nil, fail("invalid_params", "Réaction manquante.")
			}
			if p.Remove {
				r, e = b.raw(ctx, "DELETE", messagePath(p.ChatID, p.MessageID)+"/reactions/"+url.PathEscape(p.ReactionKey), nil)
			} else {
				r, e = b.raw(ctx, "POST", messagePath(p.ChatID, p.MessageID)+"/reactions", object{"reactionKey": p.ReactionKey})
			}
		}
		if e == nil {
			if method == "delete" {
				b.emit("messagesDeleted", object{"chatID": p.ChatID, "ids": []string{p.MessageID}})
			}
			b.emit("messagesChanged", object{"chatID": p.ChatID})
		}
		return r, e
	}
	return nil, fail("unknown_method", "Commande inconnue.")
}

func (b *backend) send(ctx context.Context, p parameters) (any, error) {
	if strings.TrimSpace(p.Text) == "" && p.Attachment == nil {
		return nil, fail("empty_message", "Le message est vide.")
	}
	body := object{"text": p.Text}
	if p.ReplyToMessageID != "" {
		body["replyToMessageID"] = p.ReplyToMessageID
	}
	if p.Attachment != nil {
		u, err := b.upload(ctx, p.Attachment.Path)
		if err != nil {
			return nil, err
		}
		t := p.Attachment.Type
		if t == "voiceNote" {
			t = "voice-note"
		}
		if t != "" && !validAttachmentType(t) {
			return nil, fail("invalid_attachment", "Type de pièce jointe invalide.")
		}
		uploaded := object{"uploadID": u.UploadID}
		if t != "" {
			uploaded["type"] = t
		}
		if p.Attachment.FileName != "" {
			uploaded["fileName"] = p.Attachment.FileName
		}
		if p.Attachment.MimeType != "" {
			uploaded["mimeType"] = p.Attachment.MimeType
		}
		body["attachment"] = uploaded
	}
	r, err := b.raw(ctx, "POST", chatPath(p.ChatID)+"/messages", body)
	if err != nil {
		var api *beeper.Error
		if !errors.As(err, &api) || api.StatusCode >= 500 {
			return nil, fail("send_uncertain", "L’envoi n’a pas été confirmé. Vérifie la conversation avant de réessayer : le message a peut-être été envoyé.")
		}
		return nil, err
	}
	var sent struct {
		PendingMessageID string `json:"pendingMessageID"`
	}
	_ = json.Unmarshal(r, &sent)
	if sent.PendingMessageID != "" {
		b.mu.Lock()
		b.state.Pending[sent.PendingMessageID] = p.ChatID
		err = b.persistLocked()
		b.mu.Unlock()
		if err != nil {
			b.emit("warning", object{"message": "Message accepté mais son suivi local n’a pas pu être enregistré."})
		}
		go b.resolvePending(b.ctx, p.ChatID, sent.PendingMessageID)
	}
	b.emit("messagesChanged", object{"chatID": p.ChatID})
	b.emit("chatsChanged", object{})
	return r, nil
}
