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

const localCorrectionTimeout = 5 * time.Minute
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
	ctx, cancel := context.WithTimeout(parent, timeout)
	review := &correctionReview{id: id, wake: make(chan struct{}), cancel: cancel}
	b.correctionReview = review
	b.correction = object{"id": id, "provider": key, "source": p.Text, "state": "running"}
	initial := b.correction
	b.emit("correctionChanged", initial)
	b.mu.Unlock()
	defer cancel()
	var result correctionResult
	if key == "qwen" {
		result, err = correctSpelling(ctx, b.chatURL, p.Text)
	} else {
		result, err = b.correctWithGPT(ctx, p.Text)
	}
	result.ReportID = id
	report := object{"id": id, "provider": key, "source": p.Text, "state": "ready", "text": result.Text, "html": correctionHTML(p.Text, result), "explanations": result.Explanations, "skipped": result.Skipped}
	if err != nil {
		report["state"] = "error"
		report["message"] = safeError(err).Message
	}
	b.mu.Lock()
	b.correcting = false
	if review.decision == "reject" {
		b.mu.Unlock()
		return correctionResult{ReportID: id, Cancelled: true}, nil
	}
	b.correction = report
	b.emit("correctionChanged", report)
	b.mu.Unlock()
	return result, err
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
func (b *backend) correctWithGPT(ctx context.Context, source string) (correctionResult, error) {
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
	answer := ""
	for reader.Scan() {
		var record piRecord
		if json.Unmarshal(reader.Bytes(), &record) != nil {
			continue
		}
		if record.Type == "response" && record.Success != nil && !*record.Success {
			return correctionResult{}, fail("correction", record.Error)
		}
		if record.Type == "message_end" && record.Message.Role == "assistant" {
			if record.Message.StopReason == "error" {
				return correctionResult{}, fail("correction", record.Message.ErrorMessage)
			}
			answer = messageText(record.Message.Content)
		}
		if record.Type == "agent_settled" {
			return parseCorrection(source, answer)
		}
	}
	return correctionResult{}, fail("correction", "GPT n’a pas terminé la correction. Le texte reste intact.")
}
