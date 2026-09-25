package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	beeper "github.com/beeper/desktop-api-go/v5"
)

type attachment struct {
	Path     string `json:"path"`
	Type     string `json:"type"`
	SrcURL   string `json:"srcURL,omitempty"`
	FileName string `json:"fileName,omitempty"`
	MimeType string `json:"mimeType,omitempty"`
}
type draft struct {
	Text             string      `json:"text"`
	Attachment       *attachment `json:"attachment,omitempty"`
	ReplyToMessageID string      `json:"replyToMessageID,omitempty"`
}
type diskState struct {
	Version  int               `json:"version"`
	Drafts   map[string]draft  `json:"drafts"`
	Seen     map[string]int64  `json:"seen"`
	Pending  map[string]string `json:"pending"`
	LastSync time.Time         `json:"lastSync"`
}

func loadState(dir string, demo bool) (*diskState, error) {
	s := &diskState{Version: 1, Drafts: map[string]draft{}, Seen: map[string]int64{}, Pending: map[string]string{}}
	if demo {
		return s, nil
	}
	if err := os.MkdirAll(filepath.Join(dir, "attachments"), 0700); err != nil {
		return nil, err
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return nil, err
	}
	data, err := os.ReadFile(filepath.Join(dir, "state.json"))
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	if err = json.Unmarshal(data, s); err != nil {
		return nil, errors.New("state.json is invalid; preserve this file before recovering drafts")
	}
	if s.Version != 1 {
		return nil, errors.New("unsupported state version")
	}
	if s.Drafts == nil {
		s.Drafts = map[string]draft{}
	}
	if s.Seen == nil {
		s.Seen = map[string]int64{}
	}
	if s.Pending == nil {
		s.Pending = map[string]string{}
	}
	return s, nil
}
func (b *backend) persistLocked() error {
	if b.demo {
		return nil
	}
	cutoff := time.Now().Add(-30 * 24 * time.Hour).Unix()
	for id, ts := range b.state.Seen {
		if ts < cutoff {
			delete(b.state.Seen, id)
		}
	}
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
func localPath(path string) (string, error) {
	if strings.HasPrefix(path, "file:") {
		u, err := url.Parse(path)
		if err != nil || (u.Host != "" && u.Host != "localhost") {
			return "", fail("invalid_file", "Le fichier doit être local.")
		}
		path = u.Path
	}
	if !filepath.IsAbs(path) {
		return "", fail("invalid_file", "Le fichier doit avoir un chemin absolu.")
	}
	return filepath.Clean(path), nil
}
func fileURL(path string) string { return (&url.URL{Scheme: "file", Path: path}).String() }
func validAttachmentType(t string) bool {
	switch t {
	case "image", "video", "audio", "file", "gif", "voice-note", "sticker":
		return true
	}
	return false
}
func attachmentType(m string) string {
	switch {
	case m == "image/gif":
		return "gif"
	case strings.HasPrefix(m, "image/"):
		return "image"
	case strings.HasPrefix(m, "video/"):
		return "video"
	case strings.HasPrefix(m, "audio/"):
		return "audio"
	}
	return "file"
}
func (b *backend) stage(path, t string) (*attachment, error) {
	if b.demo {
		return nil, fail("demo", "Les pièces jointes réelles sont désactivées dans la démonstration.")
	}
	path, err := localPath(path)
	if err != nil {
		return nil, err
	}
	in, err := os.Open(path)
	if err != nil {
		return nil, fail("invalid_file", "Impossible de lire ce fichier.")
	}
	defer in.Close()
	info, err := in.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > 500*1024*1024 {
		return nil, fail("invalid_file", "Choisis un fichier ordinaire de moins de 500 Mio.")
	}
	header := make([]byte, 512)
	n, _ := in.Read(header)
	_, err = in.Seek(0, io.SeekStart)
	if err != nil {
		return nil, err
	}
	m := mime.TypeByExtension(filepath.Ext(path))
	if m == "" {
		m = http.DetectContentType(header[:n])
	}
	if t == "" {
		t = attachmentType(m)
	}
	if t == "voiceNote" {
		t = "voice-note"
	}
	if !validAttachmentType(t) {
		return nil, fail("invalid_file", "Type de média invalide.")
	}
	out, err := os.CreateTemp(filepath.Join(b.stateDir, "attachments"), "attachment-*"+filepath.Ext(path))
	if err != nil {
		return nil, err
	}
	name := out.Name()
	ok := false
	defer func() {
		out.Close()
		if !ok {
			os.Remove(name)
		}
	}()
	written, err := io.Copy(out, io.LimitReader(in, 500*1024*1024+1))
	if err != nil {
		return nil, err
	}
	if written > 500*1024*1024 {
		return nil, fail("invalid_file", "Ce fichier dépasse 500 Mio.")
	}
	if err = out.Sync(); err != nil {
		return nil, err
	}
	ok = true
	return &attachment{Path: name, SrcURL: fileURL(name), Type: t, FileName: info.Name(), MimeType: m}, nil
}
func (b *backend) prepareRecording() (*attachment, error) {
	if b.demo {
		return nil, fail("demo", "L’enregistrement réel est désactivé dans la démonstration.")
	}
	f, err := os.CreateTemp(filepath.Join(b.stateDir, "attachments"), "vocal-*.ogg")
	if err != nil {
		return nil, err
	}
	f.Close()
	return &attachment{Path: f.Name(), SrcURL: fileURL(f.Name()), Type: "voice-note", FileName: "Message vocal.ogg", MimeType: "audio/ogg"}, nil
}
func (b *backend) discard(path string) error {
	if b.demo {
		return nil
	}
	path, err := localPath(path)
	if err != nil {
		return err
	}
	if filepath.Dir(path) != filepath.Join(b.stateDir, "attachments") {
		return fail("invalid_file", "Seules les copies préparées par cette application peuvent être retirées.")
	}
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fail("invalid_file", "Ce chemin n’est pas une pièce jointe préparée.")
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, d := range b.state.Drafts {
		if d.Attachment != nil && d.Attachment.Path == path {
			return fail("attachment_in_use", "La pièce jointe est encore utilisée par un brouillon.")
		}
	}
	return os.Remove(path)
}
func (b *backend) clipboard(ctx context.Context) (*attachment, error) {
	if b.demo {
		return nil, fail("demo", "Le presse-papiers réel est désactivé dans la démonstration.")
	}
	types, err := exec.CommandContext(ctx, "wl-paste", "--list-types").Output()
	if err != nil {
		return nil, fail("clipboard_empty", "Aucune image disponible dans le presse-papiers.")
	}
	m := ""
	ext := ""
	for _, candidate := range []string{"image/png", "image/gif", "image/jpeg", "image/webp"} {
		for _, line := range strings.Split(string(types), "\n") {
			if line == candidate {
				m = candidate
				break
			}
		}
		if m != "" {
			break
		}
	}
	switch m {
	case "image/png":
		ext = ".png"
	case "image/gif":
		ext = ".gif"
	case "image/jpeg":
		ext = ".jpg"
	case "image/webp":
		ext = ".webp"
	default:
		return nil, fail("clipboard_empty", "Le presse-papiers ne contient pas d’image prise en charge.")
	}
	f, err := os.CreateTemp(filepath.Join(b.stateDir, "attachments"), "clipboard-*"+ext)
	if err != nil {
		return nil, err
	}
	name := f.Name()
	ok := false
	defer func() {
		f.Close()
		if !ok {
			os.Remove(name)
		}
	}()
	cmd := exec.CommandContext(ctx, "wl-paste", "--no-newline", "--type", m)
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err = cmd.Start(); err != nil {
		return nil, err
	}
	n, copyErr := io.Copy(f, io.LimitReader(stdout, 100*1024*1024+1))
	if copyErr != nil || n > 100*1024*1024 {
		_ = cmd.Process.Kill()
	}
	err = cmd.Wait()
	if err != nil || copyErr != nil || n > 100*1024*1024 {
		return nil, fail("clipboard_error", "Impossible de copier cette image (limite de 100 Mio).")
	}
	ok = true
	return &attachment{Path: name, SrcURL: fileURL(name), Type: attachmentType(m), FileName: "Image collée" + ext, MimeType: m}, nil
}
func (b *backend) upload(ctx context.Context, path string) (*beeper.AssetUploadResponse, error) {
	path, err := localPath(path)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fail("invalid_file", "La pièce jointe n’est plus accessible.")
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil || !stat.Mode().IsRegular() || stat.Size() > 500*1024*1024 {
		return nil, fail("invalid_file", "Pièce jointe invalide ou trop volumineuse (500 Mio maximum).")
	}
	c, err := b.api()
	if err != nil {
		return nil, err
	}
	r, err := c.Assets.Upload(ctx, beeper.AssetUploadParams{File: f})
	if err == nil && (r.UploadID == "" || r.Error != "") {
		return nil, fail("upload_failed", "Beeper n’a pas pu préparer la pièce jointe.")
	}
	return r, err
}
