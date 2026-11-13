// quickshell-assistant serves the Qwen and OpenAI conversations of the
// Quickshell bottom notch through pi, and the local spelling correction.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"
	"time"
)

const ollamaURL = "http://127.0.0.1:11434/api/chat"

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

func safeError(err error) *rpcError {
	var r *rpcError
	if errors.As(err, &r) {
		return r
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return &rpcError{"timeout", "The local model did not respond in time."}
	}
	return &rpcError{"unavailable", "Action unavailable. Check that Ollama is running."}
}

type parameters struct {
	Action       string `json:"action"`
	ReportID     string `json:"reportId"`
	Status       string `json:"status"`
	Review       bool   `json:"review"`
	Conversation string `json:"conversation"`
	Text         string `json:"text"`
	Query        string `json:"query"`
	Cursor       string `json:"cursor"`
	Level        string `json:"level"`
}

type backend struct {
	mu        sync.Mutex
	writeMu   sync.Mutex
	out       io.Writer
	ctx       context.Context
	stateDir  string
	state     *diskState
	chatURL   string
	piCommand []string
	// Screenshot folder, relative to the home folder or absolute; empty: none.
	screenshots      string
	workDir          string
	runtimes         map[string]*conversationRuntime
	unloading        bool
	revision         uint64
	correcting       bool
	correction       object
	correctionReview *correctionReview
}

func main() {
	nativeCorrection := flag.Bool("correction-native", false, "Chrome native messaging host for local spelling correction")
	flag.Bool("stdio", true, "JSONL protocol on stdin/stdout (default)")
	flag.Parse()
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	if *nativeCorrection {
		if err := serveNativeCorrection(ctx, os.Stdin, os.Stdout, ""); err != nil {
			fmt.Fprintln(os.Stderr, "Native correction request failed.")
		}
		return
	}
	stateDir := os.Getenv("XDG_STATE_HOME")
	if stateDir == "" {
		home, _ := os.UserHomeDir()
		stateDir = filepath.Join(home, ".local", "state")
	}
	b, err := newBackend(ctx, os.Stdout, filepath.Join(stateDir, "quickshell-assistant"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "quickshell-assistant: cannot open private local state:", err)
		os.Exit(1)
	}
	go func() { <-ctx.Done(); os.Stdin.Close() }()
	if closeSocket, err := b.serveCorrectionSocket(); err == nil {
		defer closeSocket()
	} else {
		fmt.Fprintln(os.Stderr, "Correction panel bridge unavailable.")
	}
	if err := b.serve(os.Stdin); err != nil {
		fmt.Fprintln(os.Stderr, "quickshell-assistant: invalid input stream")
	}
	b.shutdown()
	cancel()
}

func newBackend(ctx context.Context, out io.Writer, dir string) (*backend, error) {
	state, err := loadState(dir)
	if err != nil {
		return nil, err
	}
	// A reply cannot survive a restart; never present it as still running.
	for _, c := range state.Conversations {
		for i := range c.Messages {
			if c.Messages[i].State == "generating" {
				c.Messages[i].State = "interrupted"
			}
		}
	}
	pi := os.Getenv("QUICKSHELL_ASSISTANT_PI")
	if pi == "" {
		pi = "pi"
	}
	// pi works from the file system root: both agents reach the whole computer
	// (Qwen still only reads), and absolute paths need no home-relative prefix.
	return &backend{ctx: ctx, out: out, stateDir: dir, state: state, chatURL: ollamaURL,
		piCommand: []string{pi}, screenshots: os.Getenv("QUICKSHELL_ASSISTANT_SCREENSHOTS"), workDir: "/", runtimes: map[string]*conversationRuntime{}}, nil
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
	// Unloading and correction wait on Ollama. Everything else is ordered and
	// immediate, so a stop or reset is never queued behind a network request.
	slots := make(chan struct{}, 4)
	respond := func(req request, p parameters) {
		timeout := 90 * time.Second
		if req.Method == "correctText" {
			timeout = correctionBridgeTimeout
		}
		ctx, cancel := context.WithTimeout(b.ctx, timeout)
		defer cancel()
		result, err := b.handle(ctx, req.Method, p)
		if err != nil {
			b.write(object{"id": req.ID, "error": safeError(err)})
		} else {
			b.write(object{"id": req.ID, "result": result})
		}
	}
	s := bufio.NewScanner(in)
	s.Buffer(make([]byte, 64*1024), 1024*1024)
	for s.Scan() {
		var req request
		if err := json.Unmarshal(s.Bytes(), &req); err != nil || len(req.ID) == 0 || req.Method == "" {
			b.write(object{"id": nil, "error": &rpcError{"invalid_request", "Invalid JSONL request."}})
			continue
		}
		var p parameters
		if len(req.Params) > 0 && string(req.Params) != "null" {
			if err := json.Unmarshal(req.Params, &p); err != nil {
				b.write(object{"id": req.ID, "error": &rpcError{"invalid_params", "Invalid parameters."}})
				continue
			}
		}
		if req.Method != "unload" && req.Method != "correctText" {
			respond(req, p)
			continue
		}
		select {
		case slots <- struct{}{}:
			jobs.Add(1)
			go func() { defer jobs.Done(); defer func() { <-slots }(); respond(req, p) }()
		default:
			b.write(object{"id": req.ID, "error": &rpcError{"busy", "Several actions are running. Try again in a moment."}})
		}
	}
	return s.Err()
}

func (b *backend) shutdown() {
	b.mu.Lock()
	agents := []*piAgent{}
	for _, r := range b.runtimes {
		if r.agent != nil {
			agents = append(agents, r.agent)
			r.agent = nil
		}
	}
	b.mu.Unlock()
	var wait sync.WaitGroup
	for _, agent := range agents {
		wait.Add(1)
		go func() { defer wait.Done(); agent.stop() }()
	}
	wait.Wait()
}

func (b *backend) handle(ctx context.Context, method string, p parameters) (any, error) {
	if method == "correctText" {
		return b.runCorrection(ctx, p)
	}
	if method == "finishCorrection" {
		return b.finishCorrection(p)
	}
	if method == "decideCorrection" {
		return b.decideCorrection(p)
	}
	if method == "unload" {
		return b.unload(ctx)
	}
	key, err := conversationKey(p.Conversation)
	if err != nil {
		return nil, err
	}
	switch method {
	case "status":
		b.mu.Lock()
		defer b.mu.Unlock()
		snapshot := b.snapshotLocked(key)
		snapshot["selected"] = b.state.Selected
		return snapshot, nil
	case "select":
		b.mu.Lock()
		defer b.mu.Unlock()
		if b.state.Selected != key {
			b.state.Selected = key
			if err := b.persistLocked(); err != nil {
				return nil, fail("storage", "Could not save the selected conversation.")
			}
		}
		return object{"selected": key}, nil
	case "messages":
		b.mu.Lock()
		defer b.mu.Unlock()
		return b.pageLocked(key, p.Cursor)
	case "search":
		b.mu.Lock()
		defer b.mu.Unlock()
		return b.searchLocked(key, p.Query), nil
	case "send":
		return b.send(key, p.Text)
	case "setThinking":
		return b.setThinking(key, p.Level)
	case "cancel":
		b.cancel(key)
		return object{}, nil
	case "reset":
		return b.reset(key)
	case "getDraft":
		b.mu.Lock()
		defer b.mu.Unlock()
		return object{"text": b.state.Conversations[key].Draft}, nil
	case "saveDraft":
		if len(p.Text) > 64*1024 {
			return nil, fail("invalid_params", "The draft is too long to save.")
		}
		b.mu.Lock()
		defer b.mu.Unlock()
		c := b.state.Conversations[key]
		before := c.Draft
		c.Draft = p.Text
		if err := b.persistLocked(); err != nil {
			c.Draft = before
			return nil, fail("storage", "Could not save the draft.")
		}
		return object{"text": p.Text}, nil
	}
	return nil, fail("unknown_method", "Unknown command.")
}
