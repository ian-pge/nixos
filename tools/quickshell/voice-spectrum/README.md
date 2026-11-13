# Dictation spectrum

`quickshell-voice-spectrum` reads mono float PCM from PipeWire's default input
and emits NDJSON `{ "bands": [19 values in 0..1] }`. DictationController starts
it only while VoxType is recording and stops it on transcription, cancellation,
or shell shutdown. It stores no audio. Termination also stops `pw-record`.

The microphone route matches this repository's VoxType `audio.device = "default"`
through PipeWire ALSA. If VoxType is changed to an explicit device, change the
collector's `pw-record --target` accordingly; it must not visualize another mic.

The spectrum uses overlapping Hann windows and logarithmic bands from 100 to
6400 Hz. Amplitudes have one fixed dBFS scale: no automatic gain, running peak,
or per-frame normalization. The view smooths bar heights independently of gain.
VoxType's existing activity threshold gates the view; missing audio or spectrum
frames expire after 250 ms. A missing collector leaves stationary dots.

Run `node --test tools/quickshell/voice-spectrum/spectrum_test.mjs` from the
repository root. Tests use synthetic PCM and a fake recorder, never the mic.
The desktop regression runner also includes these tests. For offline analysis,
`node tools/quickshell/voice-spectrum/capture.mjs --stdin` accepts f32le PCM at
16 kHz. Build with `nix build .#quickshellVoiceSpectrum`.
