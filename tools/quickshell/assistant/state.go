package main

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// One conversation per model. Its pi session holds the model context; the
// messages here are what the panel displays, independently of compaction.
type conversationState struct {
	Messages  []chatMessage `json:"messages"`
	Draft     string        `json:"draft"`
	SessionID string        `json:"sessionID"`
	Thinking  string        `json:"thinking,omitempty"`
}

// One private file holds every conversation, its draft and the selection.
// Version 1 held the single Qwen conversation and is migrated on load.
type diskState struct {
	Version       int                           `json:"version"`
	Selected      string                        `json:"selected"`
	Conversations map[string]*conversationState `json:"conversations"`
	Messages      []chatMessage                 `json:"messages,omitempty"`
	Draft         string                        `json:"draft,omitempty"`
}

func newSessionID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func loadState(dir string) (*diskState, error) {
	s := &diskState{Version: 2}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, err
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return nil, err
	}
	data, err := os.ReadFile(filepath.Join(dir, "state.json"))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	if err == nil {
		if err = json.Unmarshal(data, s); err != nil {
			return nil, errors.New("state.json is invalid; preserve this file before recovering the conversations")
		}
		switch s.Version {
		case 1:
			s.Conversations = map[string]*conversationState{"qwen": {Messages: s.Messages, Draft: s.Draft}}
			s.Messages, s.Draft, s.Version = nil, "", 2
		case 2:
		default:
			return nil, errors.New("unsupported state version")
		}
	}
	if s.Conversations == nil {
		s.Conversations = map[string]*conversationState{}
	}
	for _, key := range conversationKeys {
		c := s.Conversations[key]
		if c == nil {
			c = &conversationState{}
			s.Conversations[key] = c
		}
		if c.Messages == nil {
			c.Messages = []chatMessage{}
		}
		if c.SessionID == "" {
			c.SessionID = newSessionID()
		}
	}
	if _, ok := specs[s.Selected]; !ok {
		s.Selected = conversationKeys[0]
	}
	return s, nil
}

// Write atomically: a crash leaves either the previous or the new state.
// CreateTemp's 0600 mode keeps the conversations private.
func (b *backend) persistLocked() error {
	data, err := json.Marshal(b.state)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(b.stateDir, ".state-*")
	if err != nil {
		return err
	}
	name := f.Name()
	defer os.Remove(name)
	if _, err = f.Write(data); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(name, filepath.Join(b.stateDir, "state.json"))
}
