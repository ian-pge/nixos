package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func errorCode(err error) string {
	var e *rpcError
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

func TestSaveAttachmentNeverReplacesDownloads(t *testing.T) {
	root := t.TempDir()
	downloads := filepath.Join(root, "Téléchargements")
	t.Setenv("XDG_DOWNLOAD_DIR", downloads)
	source := filepath.Join(root, "cache", "a1b2c3")
	if err := os.MkdirAll(filepath.Dir(source), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(source, []byte("jpeg bytes"), 0o600); err != nil {
		t.Fatal(err)
	}
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		var request object
		_ = json.NewDecoder(r.Body).Decode(&request)
		if r.URL.Path == "/v1/assets/download" && request["url"] == "mxc://beeper.local/photo" {
			jsonResponse(w, object{"srcURL": fileURL(source)})
			return
		}
		jsonResponse(w, object{"error": "not found"})
	})
	save := func(p parameters) string {
		t.Helper()
		result, err := b.saveAttachment(b.ctx, p)
		if err != nil {
			t.Fatalf("%+v: %v", p, err)
		}
		saved := result.(object)
		path := saved["path"].(string)
		if filepath.Dir(path) != downloads || saved["name"] != filepath.Base(path) {
			t.Fatalf("saved outside the download folder: %v", saved)
		}
		if data, err := os.ReadFile(path); err != nil || string(data) != "jpeg bytes" {
			t.Fatalf("wrong copy at %s", path)
		}
		return filepath.Base(path)
	}
	if name := save(parameters{URL: fileURL(source), FileName: "Vacances.jpg"}); name != "Vacances.jpg" {
		t.Fatalf("original name not kept: %s", name)
	}
	if name := save(parameters{URL: source, FileName: "Vacances.jpg"}); name != "Vacances (2).jpg" {
		t.Fatalf("an existing download was not preserved: %s", name)
	}
	if name := save(parameters{URL: "mxc://beeper.local/photo", MimeType: "image/png"}); !strings.HasPrefix(name, "beeper-") || !strings.HasSuffix(name, ".png") {
		t.Fatalf("remote media without a name: %s", name)
	}
	if name := save(parameters{URL: fileURL(source), FileName: "../../.config/evil"}); name != "evil" {
		t.Fatalf("a file name must not leave the download folder: %s", name)
	}
	for _, tc := range []struct {
		p    parameters
		code string
	}{
		{parameters{}, "invalid_params"},
		{parameters{URL: filepath.Join(root, "missing.jpg")}, "invalid_file"},
		{parameters{URL: filepath.Join(root, "cache")}, "invalid_file"},
		{parameters{URL: "mxc://beeper.local/missing"}, "invalid_file"},
	} {
		if _, err := b.saveAttachment(b.ctx, tc.p); errorCode(err) != tc.code {
			t.Fatalf("%+v: got %v, want %s", tc.p, err, tc.code)
		}
	}
	b.demo = true
	if _, err := b.saveAttachment(b.ctx, parameters{URL: "mxc://beeper.local/photo"}); errorCode(err) != "demo" {
		t.Fatalf("the demo must not fetch remote media: %v", err)
	}
	if name := save(parameters{URL: fileURL(source), FileName: "Démo.jpg"}); name != "Démo.jpg" {
		t.Fatalf("local media is still saved in the demo: %s", name)
	}
}

func TestDownloadDirFollowsXDGUserDirs(t *testing.T) {
	home, config := t.TempDir(), t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", config)
	t.Setenv("XDG_DOWNLOAD_DIR", "")
	if got := downloadDir(); got != filepath.Join(home, "Downloads") {
		t.Fatalf("default: %s", got)
	}
	write := func(value string) {
		if err := os.WriteFile(filepath.Join(config, "user-dirs.dirs"), []byte("# xdg-user-dirs\nXDG_DESKTOP_DIR=\"$HOME/Bureau\"\nXDG_DOWNLOAD_DIR="+value+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write(`"$HOME/Téléchargements"`)
	if got := downloadDir(); got != filepath.Join(home, "Téléchargements") {
		t.Fatalf("user-dirs.dirs ignored: %s", got)
	}
	write(`"$HOME/"`)
	if got := downloadDir(); got != filepath.Join(home, "Downloads") {
		t.Fatalf("a disabled directory must not save into the home folder: %s", got)
	}
	t.Setenv("XDG_DOWNLOAD_DIR", "/srv/downloads")
	if got := downloadDir(); got != "/srv/downloads" {
		t.Fatalf("environment override ignored: %s", got)
	}
}
