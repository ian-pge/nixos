package main

import (
	"bufio"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// One long-lived `pi --mode rpc` process per conversation, started on the
// first message. Its tool allowlist is fixed at launch, so Qwen's read-only
// boundary cannot be changed from the chat.
type piAgent struct {
	cmd     *exec.Cmd
	writeMu sync.Mutex
	stdin   io.WriteCloser
	exited  chan struct{}
}

// The reply shown for one prompt: the final text of each finished assistant
// message and one line per tool call, then the message still streaming.
type agentRun struct {
	replyID   string
	committed strings.Builder
	current   string
	errorMsg  string
	lastEmit  time.Time
	done      chan struct{}
}

type conversationRuntime struct {
	agent         *piAgent
	run           *agentRun
	resetRevision uint64
}

func appendBlock(b *strings.Builder, text string) {
	if text = strings.TrimSpace(text); text == "" {
		return
	}
	if b.Len() > 0 {
		b.WriteString("\n\n")
	}
	b.WriteString(text)
}

func (run *agentRun) text() string {
	var all strings.Builder
	all.WriteString(run.committed.String())
	appendBlock(&all, run.current)
	return all.String()
}

// Text blocks of a message; thinking and tool-call blocks are not shown.
func messageText(raw json.RawMessage) string {
	var blocks []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	if json.Unmarshal(raw, &blocks) != nil {
		return ""
	}
	var text strings.Builder
	for _, block := range blocks {
		if block.Type == "text" {
			text.WriteString(block.Text)
		}
	}
	return text.String()
}

// A one-line Markdown summary of each tool call, kept in the reply text.
func toolLine(name string, args map[string]any) string {
	detail := ""
	for _, field := range []string{"command", "path", "pattern", "file_path"} {
		if value, ok := args[field].(string); ok && value != "" {
			detail = value
			break
		}
	}
	detail = strings.Join(strings.Fields(strings.ReplaceAll(detail, "`", "'")), " ")
	if len([]rune(detail)) > 160 {
		detail = string([]rune(detail)[:159]) + "…"
	}
	line := "> ▸ **" + strings.ReplaceAll(name, "*", "") + "**"
	if detail != "" {
		line += " · `" + detail + "`"
	}
	return line
}

func (a *piAgent) send(command object) error {
	data, err := json.Marshal(command)
	if err != nil {
		return err
	}
	a.writeMu.Lock()
	defer a.writeMu.Unlock()
	_, err = a.stdin.Write(append(data, '\n'))
	return err
}

// Closing stdin asks pi for an orderly shutdown; a stuck process is killed.
func (a *piAgent) stop() {
	a.stdin.Close()
	select {
	case <-a.exited:
	case <-time.After(3 * time.Second):
		_ = a.cmd.Process.Kill()
	}
}

// Called with b.mu held.
func (b *backend) agentArgs(key, sessionID string) []string {
	spec := specs[key]
	home, _ := os.UserHomeDir()
	prompt := spec.Prompt
	if spec.Screenshots && b.screenshots != "" {
		prompt += " " + screenshotPrompt(b.screenshots)
	}
	return []string{"--mode", "rpc", "--model", spec.Model, "--tools", spec.Tools,
		"--thinking", b.thinkingLevelLocked(key),
		"--session-dir", filepath.Join(b.stateDir, "sessions", key), "--session-id", sessionID,
		"--append-system-prompt", strings.ReplaceAll(prompt, "$HOME", home),
		// Only the chosen tools: no user extensions, skills, MCP servers or
		// instruction files found in the working directory.
		"--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes",
		"--no-context-files", "--no-mcp", "--no-approve"}
}

// Called with b.mu held.
func (b *backend) startAgent(key, sessionID string) (*piAgent, error) {
	cmd := exec.Command(b.piCommand[0], append(append([]string{}, b.piCommand[1:]...), b.agentArgs(key, sessionID)...)...)
	cmd.Dir = b.workDir
	cmd.Env = append(os.Environ(), "PI_SKIP_VERSION_CHECK=1", "PI_TELEMETRY=0")
	cmd.Stderr = io.Discard
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	agent := &piAgent{cmd: cmd, stdin: stdin, exited: make(chan struct{})}
	go func() {
		// Split only on LF: JSON strings may contain U+2028/U+2029.
		reader := bufio.NewReaderSize(stdout, 64*1024)
		for {
			line, err := reader.ReadBytes('\n')
			if len(line) > 0 {
				b.handleRecord(key, agent, line)
			}
			if err != nil {
				break
			}
		}
		_ = cmd.Wait()
		close(agent.exited)
		b.agentExited(key, agent)
	}()
	return agent, nil
}

func (b *backend) agentExited(key string, agent *piAgent) {
	b.mu.Lock()
	r := b.runtime(key)
	if r.agent != agent {
		b.mu.Unlock()
		return
	}
	r.agent = nil
	run := r.run
	b.mu.Unlock()
	if run != nil {
		b.finishRun(key, run, "failed", "pi stopped unexpectedly.")
	}
}

type piRecord struct {
	Type     string         `json:"type"`
	Command  string         `json:"command"`
	Success  *bool          `json:"success"`
	Error    string         `json:"error"`
	ToolName string         `json:"toolName"`
	Args     map[string]any `json:"args"`
	IsError  bool           `json:"isError"`
	Aborted  bool           `json:"aborted"`
	Event    struct {
		Type  string `json:"type"`
		Delta string `json:"delta"`
	} `json:"assistantMessageEvent"`
	Message struct {
		Role         string          `json:"role"`
		Content      json.RawMessage `json:"content"`
		StopReason   string          `json:"stopReason"`
		ErrorMessage string          `json:"errorMessage"`
	} `json:"message"`
}

func (b *backend) handleRecord(key string, agent *piAgent, line []byte) {
	var record piRecord
	if json.Unmarshal(line, &record) != nil {
		return
	}
	b.mu.Lock()
	r := b.runtime(key)
	run := r.run
	if r.agent != agent || run == nil {
		b.mu.Unlock()
		return
	}
	emit := false
	switch record.Type {
	case "response":
		if record.Command == "prompt" && record.Success != nil && !*record.Success {
			b.mu.Unlock()
			b.finishRun(key, run, "failed", record.Error)
			return
		}
	case "message_start":
		if record.Message.Role == "assistant" {
			run.current = messageText(record.Message.Content)
			emit = run.current != ""
		}
	case "message_update":
		if record.Event.Type == "text_delta" && record.Event.Delta != "" {
			run.current += record.Event.Delta
			emit = time.Since(run.lastEmit) >= 50*time.Millisecond
		}
	case "message_end":
		if record.Message.Role == "assistant" {
			// The finished message is authoritative over the streamed deltas.
			if final := messageText(record.Message.Content); final != "" || record.Message.StopReason != "aborted" {
				run.current = final
			}
			appendBlock(&run.committed, run.current)
			run.current = ""
			if record.Message.StopReason == "error" {
				run.errorMsg = record.Message.ErrorMessage
			}
			emit = true
		}
	case "tool_execution_start":
		appendBlock(&run.committed, toolLine(record.ToolName, record.Args))
		emit = true
	case "tool_execution_end":
		if record.IsError {
			run.committed.WriteString(" — failed")
		}
		// Back to thinking until the next text arrives.
		emit = true
	case "agent_settled":
		state := "complete"
		switch {
		case record.Aborted:
			state = "stopped"
		case run.errorMsg != "" || strings.TrimSpace(run.text()) == "":
			state = "failed"
		}
		detail := run.errorMsg
		b.mu.Unlock()
		b.finishRun(key, run, state, detail)
		return
	}
	if !emit {
		b.mu.Unlock()
		return
	}
	run.lastEmit = time.Now()
	b.updateReplyLocked(key, run, "generating")
}

// Called with b.mu held; releases it.
func (b *backend) updateReplyLocked(key string, run *agentRun, state string) {
	c := b.state.Conversations[key]
	var changed object
	for i := range c.Messages {
		if c.Messages[i].ID == run.replyID {
			c.Messages[i].Content = run.text()
			c.Messages[i].State = state
			changed = c.Messages[i].display()
			changed["thinking"] = state == "generating" && strings.TrimSpace(run.current) == ""
			break
		}
	}
	if changed == nil {
		b.mu.Unlock()
		return
	}
	b.revision++
	var persistErr error
	if state != "generating" {
		persistErr = b.persistLocked()
	}
	snapshot := b.metadataLocked(key)
	// Stream only the changing bubble; older delegates keep their snapshots.
	snapshot["items"] = []object{changed}
	b.mu.Unlock()
	b.emit("changed", snapshot)
	if persistErr != nil {
		b.emit("warning", object{"message": "Could not save the reply to disk."})
	}
}

// Ends a run once. A reset may already have replaced it: a late end must
// neither reappear nor clear the next reply.
func (b *backend) finishRun(key string, run *agentRun, state, detail string) {
	b.mu.Lock()
	r := b.runtime(key)
	if r.run != run {
		b.mu.Unlock()
		return
	}
	r.run = nil
	appendBlock(&run.committed, run.current)
	run.current = ""
	if detail != "" && state == "failed" {
		appendBlock(&run.committed, "> "+strings.Join(strings.Fields(detail), " "))
	}
	b.updateReplyLocked(key, run, state)
	close(run.done)
}

// Screenshots are only opened when the user mentions one: nothing is sent to
// the provider otherwise. Print names them by date and time.
func screenshotPrompt(dir string) string {
	if !filepath.IsAbs(dir) {
		dir = filepath.Join("$HOME", dir)
	}
	return "The user's screenshots are in " + dir + ", saved with the Print key and named by date and time, so the newest sort last by name. " +
		"When the user mentions a screenshot or a capture (« capture », « capture d'écran », « ce que je vois »), list that folder, take the most recent file or files they mean, and look at them with the read tool. " +
		"Do not open them otherwise."
}
