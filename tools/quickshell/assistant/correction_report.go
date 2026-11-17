package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"
)

const localCorrectionTimeout = 75 * time.Second
const correctionBridgeTimeout = localCorrectionTimeout + 10*time.Second

func correctionSocketPath() string {
	return filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "quickshell-assistant", "correction.sock")
}

func (b *backend) serveCorrectionSocket() (func(), error) {
	if os.Getenv("XDG_RUNTIME_DIR") == "" {
		return nil, fmt.Errorf("missing runtime directory")
	}
	path := correctionSocketPath()
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return nil, err
	}
	if conn, err := net.DialTimeout("unix", path, 100*time.Millisecond); err == nil {
		conn.Close()
		return nil, fmt.Errorf("correction service already running")
	}
	os.Remove(path)
	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, err
	}
	os.Chmod(path, 0600)
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				conn.SetDeadline(time.Now().Add(correctionBridgeTimeout))
				var p parameters
				if json.NewDecoder(io.LimitReader(conn, 64*1024)).Decode(&p) != nil {
					return
				}
				var result any
				var err error
				if p.Action == "status" {
					result, err = b.finishCorrection(p)
				} else if p.Action == "decide" {
					result, err = b.decideCorrection(p)
				} else if p.Action == "wait" {
					result, err = b.waitCorrectionDecision(b.ctx, p.ReportID)
				} else if p.Action == "correct" {
					result, err = b.runCorrection(b.ctx, p)
				} else {
					err = fmt.Errorf("invalid action")
				}
				if err != nil {
					json.NewEncoder(conn).Encode(object{"ok": false, "error": safeError(err).Message})
				} else {
					json.NewEncoder(conn).Encode(object{"ok": true, "result": result})
				}
			}()
		}
	}()
	return func() { listener.Close(); os.Remove(path) }, nil
}

func requestCorrectionPanel(ctx context.Context, p parameters) (object, error) {
	conn, err := (&net.Dialer{}).DialContext(ctx, "unix", correctionSocketPath())
	if err != nil {
		return nil, fail("correction", "Le panneau d’IA est indisponible. Ouvre Quickshell.")
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(correctionBridgeTimeout))
	if err = json.NewEncoder(conn).Encode(p); err != nil {
		return nil, err
	}
	var result object
	err = json.NewDecoder(io.LimitReader(conn, 512*1024)).Decode(&result)
	return result, err
}

func correctionHTML(source string, result correctionResult) string {
	runes := []rune(source)
	var out strings.Builder
	cursor := 0
	out.WriteString(`<p style="white-space:pre-wrap">`)
	for _, e := range result.Edits {
		out.WriteString(html.EscapeString(string(runes[cursor:e.Start])))
		out.WriteString(`<span style="color:#ed8796;font-weight:600">` + html.EscapeString(e.Replacement) + `</span>`)
		cursor = e.End
	}
	out.WriteString(html.EscapeString(string(runes[cursor:])))
	out.WriteString("</p>")
	return strings.ReplaceAll(out.String(), "\n", "<br/>")
}
func (b *backend) runCorrection(parent context.Context, p parameters) (correctionResult, error) {
	if !p.Review {
		return correctionResult{}, fail("upgrade", "Recharge l’extension de correction dans Chrome, puis recharge cette page.")
	}
	key, err := conversationKey(p.Conversation)
	if err != nil {
		return correctionResult{}, err
	}
	if !utf8.ValidString(p.Text) || len(p.Text) > 8000 {
		b.finishCorrection(parameters{Conversation: key, Status: "error", Text: "Sélectionne un texte de moins de 8 Ko."})
		return correctionResult{}, fail("correction", "Sélectionne un texte de moins de 8 Ko.")
	}
	b.mu.Lock()
	if b.correcting || (b.correctionReview != nil && b.correctionReview.decision == "" && b.correction["state"] == "ready") {
		b.mu.Unlock()
		return correctionResult{}, fail("busy", "Une correction est déjà en cours.")
	}
	b.correcting = true
	id := p.ReportID
	if id == "" {
		id = fmt.Sprintf("correction-%d", time.Now().UnixNano())
	}
	timeout := 75 * time.Second
	if key == "qwen" {
		timeout = localCorrectionTimeout
	}
	// The worker outlives the initial RPC: the client receives the validated
	// draft first, while explanation updates continue on the panel event stream.
	ctx, cancel := context.WithTimeout(b.ctx, timeout)
	review := &correctionReview{id: id, wake: make(chan struct{}), cancel: cancel, done: make(chan struct{})}
	b.correctionReview = review
	b.correction = object{"id": id, "provider": key, "source": p.Text, "state": "running"}
	b.emit("correctionChanged", b.correction)
	b.mu.Unlock()
	type outcome struct {
		result correctionResult
		err    error
	}
	first := make(chan outcome, 1)
	b.correctionJobs.Add(1)
	go func() {
		defer b.correctionJobs.Done()
		defer close(review.done)
		defer cancel()
		var preview *correctionResult
		publish := func(result correctionResult, explaining bool) {
			result.ReportID = id
			b.mu.Lock()
			defer b.mu.Unlock()
			if b.correctionReview != review || review.decision != "" {
				return
			}
			b.correction = object{"id": id, "provider": key, "source": p.Text, "state": "ready",
				"text": result.Text, "html": correctionHTML(p.Text, result), "explanations": result.Explanations,
				"skipped": result.Skipped, "explaining": explaining}
			b.emit("correctionChanged", b.correction)
			if preview == nil {
				first <- outcome{result: result}
			}
			copy := result
			preview = &copy
		}
		var result correctionResult
		var err error
		if key == "qwen" {
			result, err = correctSpelling(ctx, b.chatURL, p.Text)
		} else {
			result, err = b.correctWithGPT(ctx, p.Text, func(partial correctionResult) { publish(partial, true) })
		}
		b.mu.Lock()
		defer b.mu.Unlock()
		if b.correctionReview != review || review.decision != "" {
			if preview == nil {
				first <- outcome{result: correctionResult{ReportID: id, Cancelled: true}}
			}
			return
		}
		b.correcting = false
		if err != nil && preview != nil {
			// A late explanation failure cannot revoke or replace an already
			// validated draft. The user can still accept that exact proposal.
			result = *preview
		}
		result.ReportID = id
		report := object{"id": id, "provider": key, "source": p.Text, "state": "ready", "text": result.Text,
			"html": correctionHTML(p.Text, result), "explanations": result.Explanations, "skipped": result.Skipped, "explaining": false}
		if err != nil {
			if preview == nil {
				report["state"] = "error"
				report["message"] = safeError(err).Message
			} else {
				report["message"] = "Les explications n’ont pas pu être terminées. La proposition reste disponible."
			}
		}
		b.correction = report
		b.emit("correctionChanged", report)
		if preview == nil {
			first <- outcome{result: result, err: err}
		}
	}()
	select {
	case reply := <-first:
		return reply.result, reply.err
	case <-parent.Done():
		b.decideCorrection(parameters{ReportID: id, Status: "reject"})
		return correctionResult{}, parent.Err()
	}
}

func (b *backend) finishCorrection(p parameters) (any, error) {
	switch p.Status {
	case "applied", "unchanged", "cancelled", "undone", "error":
	default:
		return nil, fail("invalid_params", "Invalid correction status")
	}
	b.mu.Lock()
	if p.ReportID == "" && p.Status == "error" {
		key, _ := conversationKey(p.Conversation)
		report := object{"id": fmt.Sprintf("correction-%d", time.Now().UnixNano()), "provider": key, "state": "error", "message": p.Text, "html": "", "explanations": []correctionExplanation{}}
		b.correction = report
		b.mu.Unlock()
		b.emit("correctionChanged", report)
		return object{}, nil
	}
	if b.correction == nil || b.correction["id"] != p.ReportID {
		b.mu.Unlock()
		return object{}, nil
	}
	report := object{}
	for key, value := range b.correction {
		report[key] = value
	}
	report["state"] = p.Status
	if len(p.Text) < 500 {
		report["message"] = p.Text
	}
	b.correction = report
	b.mu.Unlock()
	b.emit("correctionChanged", report)
	return object{}, nil
}
func (b *backend) correctWithGPT(ctx context.Context, source string, progress func(correctionResult)) (correctionResult, error) {
	args := append(append([]string{}, b.piCommand[1:]...), "--mode", "rpc", "--model", specs["openai"].Model, "--thinking", "low", "--no-tools", "--no-session", "--system-prompt", correctionPrompt, "--no-extensions", "--no-skills", "--no-mcp", "--no-context-files", "--no-prompt-templates", "--no-themes")
	cmd := exec.CommandContext(ctx, b.piCommand[0], args...)
	cmd.Dir = b.workDir
	cmd.Env = append(os.Environ(), "PI_SKIP_VERSION_CHECK=1", "PI_TELEMETRY=0")
	cmd.Stderr = io.Discard
	input, err := cmd.StdinPipe()
	if err != nil {
		return correctionResult{}, err
	}
	output, err := cmd.StdoutPipe()
	if err != nil {
		return correctionResult{}, err
	}
	if err = cmd.Start(); err != nil {
		return correctionResult{}, fail("correction", "Impossible de démarrer GPT via pi.")
	}
	defer func() { input.Close(); cmd.Process.Kill(); cmd.Wait() }()
	json.NewEncoder(input).Encode(object{"type": "prompt", "message": source})
	reader := bufio.NewScanner(io.LimitReader(output, 2*1024*1024))
	reader.Buffer(make([]byte, 4096), 1024*1024)
	answer, frozenText, lastProgress := "", "", ""
	published := false
	update := func() error {
		partial, ready, err := partialCorrection(source, answer)
		if err != nil {
			return fail("correction", "La réponse n’a pas pu être vérifiée. Le texte reste intact.")
		}
		if !ready {
			return nil
		}
		if published && partial.Text != frozenText {
			return fail("correction", "La proposition a changé pendant la réponse.")
		}
		published, frozenText = true, partial.Text
		encoded, _ := json.Marshal(partial)
		if string(encoded) != lastProgress {
			lastProgress = string(encoded)
			progress(partial)
		}
		return nil
	}
	for reader.Scan() {
		var record piRecord
		if json.Unmarshal(reader.Bytes(), &record) != nil {
			continue
		}
		if record.Type == "response" && record.Success != nil && !*record.Success {
			return correctionResult{}, fail("correction", record.Error)
		}
		if record.Type == "message_start" && record.Message.Role == "assistant" {
			answer = messageText(record.Message.Content)
			if err := update(); err != nil {
				return correctionResult{}, err
			}
		}
		if record.Type == "message_update" && record.Event.Type == "text_delta" {
			answer += record.Event.Delta
			if err := update(); err != nil {
				return correctionResult{}, err
			}
		}
		if record.Type == "message_end" && record.Message.Role == "assistant" {
			if record.Message.StopReason == "error" {
				return correctionResult{}, fail("correction", record.Message.ErrorMessage)
			}
			answer = messageText(record.Message.Content)
			if err := update(); err != nil {
				return correctionResult{}, err
			}
		}
		if record.Type == "agent_settled" {
			result, err := parseCorrection(source, answer)
			if err == nil && published && result.Text != frozenText {
				return correctionResult{}, fail("correction", "La proposition a changé pendant la réponse.")
			}
			return result, err
		}
	}
	return correctionResult{}, fail("correction", "GPT n’a pas terminé la correction. Le texte reste intact.")
}
