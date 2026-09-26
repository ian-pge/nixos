package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type waveformResult struct {
	Peaks      []float64 `json:"peaks"`
	DurationMS int64     `json:"durationMs"`
}

func (b *backend) waveform(ctx context.Context, source string) (waveformResult, error) {
	empty := waveformResult{}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if source == "" {
		return empty, fail("invalid_file", "Missing audio source.")
	}
	if !strings.HasPrefix(source, "file:") && !filepath.IsAbs(source) {
		// Only the public Beeper endpoint fetches URLs. The decoder has no network.
		raw, err := b.raw(ctx, "POST", "v1/assets/download", object{"url": source})
		if err != nil {
			return empty, err
		}
		var downloaded struct {
			SrcURL string `json:"srcURL"`
		}
		if json.Unmarshal(raw, &downloaded) != nil || downloaded.SrcURL == "" {
			return empty, fail("invalid_file", "Audio is not available locally.")
		}
		source = downloaded.SrcURL
	}
	path, err := localPath(source)
	if err != nil {
		return empty, err
	}
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() > 128*1024*1024 {
		return empty, fail("invalid_file", "Audio analysis requires a regular local file under 128 MiB.")
	}
	key := fmt.Sprintf("%s:%d:%d", path, info.Size(), info.ModTime().UnixNano())
	b.mu.Lock()
	cached, exists := b.waveformCache[key]
	b.mu.Unlock()
	if exists {
		return cached, nil
	}
	cmd := exec.CommandContext(ctx, "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
		"-threads", "1", "-protocol_whitelist", "file,pipe",
		"-format_whitelist", "wav,ogg,mp3,flac,aac,mov,matroska,webm,amr,asf",
		"-i", path, "-map", "0:a:0", "-vn", "-sn", "-dn", "-ac", "1", "-ar", "8000", "-f", "s16le", "pipe:1")
	cmd.Stderr = io.Discard // Never expose file paths or codec diagnostics to QML.
	out, err := cmd.StdoutPipe()
	if err != nil || cmd.Start() != nil {
		return empty, fail("waveform", "Audio waveform unavailable.")
	}
	const limit = 32 * 1024 * 1024
	pcm, readErr := io.ReadAll(io.LimitReader(out, limit+1))
	if readErr != nil || len(pcm) > limit {
		cancel()
		_ = cmd.Wait()
		return empty, fail("waveform", "Audio exceeds the waveform analysis limit.")
	}
	if cmd.Wait() != nil || len(pcm) < 2 {
		return empty, fail("waveform", "Audio waveform unavailable.")
	}
	result := waveformFromPCM(pcm, 96)
	b.mu.Lock()
	if b.waveformCache == nil {
		b.waveformCache = make(map[string]waveformResult)
	}
	if len(b.waveformCache) >= 128 {
		for old := range b.waveformCache {
			delete(b.waveformCache, old)
			break
		}
	}
	b.waveformCache[key] = result
	b.mu.Unlock()
	return result, nil
}

// RMS energy per equal-duration interval, normalized with a gentle compression
// so quiet syllables remain readable. Silence remains silence, not random bars.
func waveformFromPCM(pcm []byte, count int) waveformResult {
	samples := len(pcm) / 2
	peaks := make([]float64, count)
	maximum := 0.0
	for i := range peaks {
		start, end := samples*i/count, samples*(i+1)/count
		energy := 0.0
		for n := start; n < end; n++ {
			value := float64(int16(binary.LittleEndian.Uint16(pcm[n*2:]))) / 32768
			energy += value * value
		}
		if end > start {
			peaks[i] = math.Sqrt(energy / float64(end-start))
			maximum = math.Max(maximum, peaks[i])
		}
	}
	if maximum > 0.0001 {
		for i := range peaks {
			peaks[i] = math.Sqrt(peaks[i] / maximum)
		}
	}
	return waveformResult{Peaks: peaks, DurationMS: int64(samples) * 1000 / 8000}
}
