package main

import (
	"bytes"
	"context"
	"encoding/binary"
	"io"
	"math"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func testWaveFile(t *testing.T) string {
	t.Helper()
	pcm := make([]byte, 8000*2)
	for i := 2000; i < 8000; i++ {
		value := int16(math.Sin(float64(i)*2*math.Pi*440/8000) * float64(i/2000) * 0.2 * 32767)
		binary.LittleEndian.PutUint16(pcm[i*2:], uint16(value))
	}
	var wav bytes.Buffer
	wav.WriteString("RIFF")
	_ = binary.Write(&wav, binary.LittleEndian, uint32(36+len(pcm)))
	wav.WriteString("WAVEfmt ")
	for _, value := range []any{uint32(16), uint16(1), uint16(1), uint32(8000), uint32(16000), uint16(2), uint16(16)} {
		_ = binary.Write(&wav, binary.LittleEndian, value)
	}
	wav.WriteString("data")
	_ = binary.Write(&wav, binary.LittleEndian, uint32(len(pcm)))
	wav.Write(pcm)
	path := filepath.Join(t.TempDir(), "voice with spaces.wav")
	if err := os.WriteFile(path, wav.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestWaveformDecodesEnvelopeAndCaches(t *testing.T) {
	t.Setenv("BEEPER_API_URL", "")
	b, err := newBackend(context.Background(), io.Discard, t.TempDir(), false)
	if err != nil {
		t.Fatal(err)
	}
	path := testWaveFile(t)
	result, err := b.waveform(b.ctx, fileURL(path))
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Peaks) != 96 || result.DurationMS != 1000 {
		t.Fatalf("unexpected waveform: %#v", result)
	}
	if result.Peaks[10] != 0 || result.Peaks[35] >= result.Peaks[60] || result.Peaks[60] >= result.Peaks[85] {
		t.Fatal("waveform does not follow actual silence and amplitude")
	}
	for _, peak := range result.Peaks {
		if peak < 0 || peak > 1 || math.IsNaN(peak) {
			t.Fatal("invalid amplitude")
		}
	}
	t.Setenv("PATH", t.TempDir())
	cached, err := b.waveform(b.ctx, path)
	if err != nil || cached.DurationMS != 1000 {
		t.Fatal("unchanged file was decoded again")
	}
}

func TestWaveformUsesPublicBeeperDownload(t *testing.T) {
	path := testWaveFile(t)
	b, _ := testBackend(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" || r.URL.Path != "/v1/assets/download" {
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		jsonResponse(w, object{"srcURL": fileURL(path)})
	})
	result, err := b.waveform(b.ctx, "mxc://beeper/fictional-audio")
	if err != nil || len(result.Peaks) != 96 {
		t.Fatalf("public download failed: %v", err)
	}
}

func TestWaveformSupportsVoiceNoteContainers(t *testing.T) {
	t.Setenv("BEEPER_API_URL", "")
	b, err := newBackend(context.Background(), io.Discard, t.TempDir(), false)
	if err != nil {
		t.Fatal(err)
	}
	wav := testWaveFile(t)
	for _, format := range []struct{ extension, codec string }{{"ogg", "libopus"}, {"m4a", "aac"}} {
		path := filepath.Join(t.TempDir(), "voice."+format.extension)
		if err := exec.Command("ffmpeg", "-nostdin", "-loglevel", "error", "-i", wav, "-c:a", format.codec, path).Run(); err != nil {
			t.Fatal(err)
		}
		result, err := b.waveform(b.ctx, path)
		if err != nil || len(result.Peaks) != 96 {
			t.Fatalf("%s waveform failed: %v", format.extension, err)
		}
	}
}

func TestWaveformRejectsNonMediaDirectoriesAndDemo(t *testing.T) {
	t.Setenv("BEEPER_API_URL", "")
	b, err := newBackend(context.Background(), io.Discard, t.TempDir(), false)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "not-audio.txt")
	if err := os.WriteFile(path, []byte("private-test-content"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, source := range []string{path, filepath.Dir(path), "file://other-machine/audio.wav"} {
		_, err := b.waveform(b.ctx, source)
		if err == nil || strings.Contains(err.Error(), "private-test-content") || strings.Contains(err.Error(), path) {
			t.Fatal("unsafe waveform error")
		}
	}
	b.demo = true
	_, err = b.handle(b.ctx, "waveform", parameters{URL: path})
	if safeError(err).Code != "demo" {
		t.Fatal("demo must never decode real files")
	}
}
