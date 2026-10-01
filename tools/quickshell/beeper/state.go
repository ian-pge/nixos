package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	Text             string        `json:"text"`
	Attachment       *attachment   `json:"attachment,omitempty"`
	Attachments      []*attachment `json:"attachments,omitempty"`
	ReplyToMessageID string        `json:"replyToMessageID,omitempty"`
	SavedDrafts      []savedDraft  `json:"savedDrafts,omitempty"`
}
type savedDraft struct {
	ID               string        `json:"id"`
	Text             string        `json:"text"`
	Attachment       *attachment   `json:"attachment,omitempty"`
	Attachments      []*attachment `json:"attachments,omitempty"`
	ReplyToMessageID string        `json:"replyToMessageID,omitempty"`
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
			return "", fail("invalid_file", "The file must be local.")
		}
		path = u.Path
	}
	if !filepath.IsAbs(path) {
		return "", fail("invalid_file", "The file must have an absolute path.")
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
		return nil, fail("demo", "Real attachments are disabled in the demo.")
	}
	path, err := localPath(path)
	if err != nil {
		return nil, err
	}
	in, err := os.Open(path)
	if err != nil {
		return nil, fail("invalid_file", "Could not read this file.")
	}
	defer in.Close()
	info, err := in.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > 500*1024*1024 {
		return nil, fail("invalid_file", "Choose a regular file smaller than 500 MiB.")
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
		return nil, fail("invalid_file", "Invalid media type.")
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
		return nil, fail("invalid_file", "This file exceeds 500 MiB.")
	}
	if err = out.Sync(); err != nil {
		return nil, err
	}
	ok = true
	return &attachment{Path: name, SrcURL: fileURL(name), Type: t, FileName: info.Name(), MimeType: m}, nil
}

// Prepare the entire selection before exposing it to the draft. A failed file
// must not leave an invisible partial selection or orphaned private copies.
func (b *backend) stageMany(paths []string) ([]*attachment, error) {
	staged := make([]*attachment, 0, len(paths))
	for _, path := range paths {
		a, err := b.stage(path, "")
		if err != nil {
			for _, previous := range staged {
				_ = b.discard(previous.Path)
			}
			return nil, err
		}
		staged = append(staged, a)
	}
	return staged, nil
}
func attachmentReferenced(path string, single *attachment, many []*attachment) bool {
	if single != nil && single.Path == path {
		return true
	}
	for _, a := range many {
		if a != nil && a.Path == path {
			return true
		}
	}
	return false
}
func (b *backend) prepareRecording() (*attachment, error) {
	if b.demo {
		return nil, fail("demo", "Recording is disabled in the demo.")
	}
	f, err := os.CreateTemp(filepath.Join(b.stateDir, "attachments"), "vocal-*.ogg")
	if err != nil {
		return nil, err
	}
	f.Close()
	return &attachment{Path: f.Name(), SrcURL: fileURL(f.Name()), Type: "voice-note", FileName: "Voice message.ogg", MimeType: "audio/ogg"}, nil
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
		return fail("invalid_file", "Only copies prepared by this app can be removed.")
	}
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fail("invalid_file", "This path is not a prepared attachment.")
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, d := range b.state.Drafts {
		if attachmentReferenced(path, d.Attachment, d.Attachments) {
			return fail("attachment_in_use", "The attachment is still used by a draft.")
		}
		for _, saved := range d.SavedDrafts {
			if attachmentReferenced(path, saved.Attachment, saved.Attachments) {
				return fail("attachment_in_use", "The attachment is still used by a saved draft.")
			}
		}
	}
	return os.Remove(path)
}
func (b *backend) clipboard(ctx context.Context) (*attachment, error) {
	if b.demo {
		return nil, fail("demo", "Clipboard access is disabled in the demo.")
	}
	types, err := exec.CommandContext(ctx, "wl-paste", "--list-types").Output()
	if err != nil {
		return nil, fail("clipboard_empty", "No image is available on the clipboard.")
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
		return nil, fail("clipboard_empty", "The clipboard does not contain a supported image.")
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
		return nil, fail("clipboard_error", "Could not copy this image (100 MiB limit).")
	}
	ok = true
	return &attachment{Path: name, SrcURL: fileURL(name), Type: attachmentType(m), FileName: "Pasted image" + ext, MimeType: m}, nil
}
func (b *backend) upload(ctx context.Context, path string) (*beeper.AssetUploadResponse, error) {
	path, err := localPath(path)
	if err != nil {
		return nil, err
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, fail("invalid_file", "The attachment is no longer accessible.")
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil || !stat.Mode().IsRegular() || stat.Size() > 500*1024*1024 {
		return nil, fail("invalid_file", "Invalid attachment or file too large (500 MiB maximum).")
	}
	c, err := b.api()
	if err != nil {
		return nil, err
	}
	r, err := c.Assets.Upload(ctx, beeper.AssetUploadParams{File: f})
	if err == nil && (r.UploadID == "" || r.Error != "") {
		return nil, fail("upload_failed", "Beeper could not prepare the attachment.")
	}
	return r, err
}

// saveAttachment copies media shown in the photo viewer into the XDG
// download directory. An existing file is never replaced: a numbered name is
// chosen instead. Remote media goes through the public assets endpoint.
func (b *backend) saveAttachment(ctx context.Context, p parameters) (any, error) {
	source := p.URL
	if source == "" {
		return nil, fail("invalid_params", "Missing media URL.")
	}
	if !strings.HasPrefix(source, "file:") && !filepath.IsAbs(source) {
		if b.demo {
			return nil, fail("demo", "Remote media is not available in the demo.")
		}
		raw, err := b.raw(ctx, "POST", "v1/assets/download", object{"url": source})
		if err != nil {
			return nil, err
		}
		var downloaded struct {
			SrcURL string `json:"srcURL"`
		}
		if json.Unmarshal(raw, &downloaded) != nil || downloaded.SrcURL == "" {
			return nil, fail("invalid_file", "This media is not available locally.")
		}
		source = downloaded.SrcURL
	}
	path, err := localPath(source)
	if err != nil {
		return nil, err
	}
	in, err := os.Open(path)
	if err != nil {
		return nil, fail("invalid_file", "Could not read this media.")
	}
	defer in.Close()
	if info, err := in.Stat(); err != nil || !info.Mode().IsRegular() {
		return nil, fail("invalid_file", "Could not read this media.")
	}
	dir := downloadDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fail("save_failed", "Could not open the download folder.")
	}
	out, err := createUnique(dir, saveName(p.FileName, p.MimeType, path))
	if err != nil {
		return nil, fail("save_failed", "Could not create the file in the download folder.")
	}
	name := out.Name()
	_, err = io.Copy(out, in)
	if closeErr := out.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		os.Remove(name)
		return nil, fail("save_failed", "Could not write the file.")
	}
	return object{"path": name, "name": filepath.Base(name)}, nil
}

// The download directory configured by xdg-user-dirs, else ~/Downloads.
func downloadDir() string {
	home, _ := os.UserHomeDir()
	if dir := os.Getenv("XDG_DOWNLOAD_DIR"); filepath.IsAbs(dir) {
		return filepath.Clean(dir)
	}
	config := os.Getenv("XDG_CONFIG_HOME")
	if !filepath.IsAbs(config) {
		config = filepath.Join(home, ".config")
	}
	if data, err := os.ReadFile(filepath.Join(config, "user-dirs.dirs")); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			value, ok := strings.CutPrefix(strings.TrimSpace(line), "XDG_DOWNLOAD_DIR=")
			if !ok {
				continue
			}
			value = strings.Trim(value, `"`)
			if rest, ok := strings.CutPrefix(value, "$HOME"); ok {
				value = home + rest
			}
			// "$HOME/" disables the directory in xdg-user-dirs.
			if filepath.IsAbs(value) && filepath.Clean(value) != filepath.Clean(home) {
				return filepath.Clean(value)
			}
		}
	}
	return filepath.Join(home, "Downloads")
}

var savedExtensions = map[string]string{
	"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "image/gif": ".gif",
	"image/heic": ".heic", "image/avif": ".avif", "video/mp4": ".mp4", "video/webm": ".webm",
	"video/quicktime": ".mov",
}

// A plain file name: the original one when known, otherwise a dated name.
func saveName(fileName, mimeType, source string) string {
	name := strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, strings.TrimSpace(filepath.Base(strings.ReplaceAll(fileName, `\`, "/"))))
	if name == "" || name == "." || name == ".." || name == "/" {
		name = "beeper-" + time.Now().Format("2006-01-02-150405")
	}
	if filepath.Ext(name) == "" {
		ext := savedExtensions[strings.ToLower(strings.TrimSpace(strings.Split(mimeType, ";")[0]))]
		if ext == "" {
			ext = filepath.Ext(source)
		}
		name += ext
	}
	return name
}

func createUnique(dir, name string) (*os.File, error) {
	ext := filepath.Ext(name)
	stem := strings.TrimSuffix(name, ext)
	for i := 1; i <= 1000; i++ {
		candidate := name
		if i > 1 {
			candidate = fmt.Sprintf("%s (%d)%s", stem, i, ext)
		}
		f, err := os.OpenFile(filepath.Join(dir, candidate), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
		if !errors.Is(err, os.ErrExist) {
			return f, err
		}
	}
	return nil, os.ErrExist
}
