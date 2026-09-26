import Quickshell
import Quickshell.Io
import QtQuick

// Reads only VoxType's public status and local audio bridge. No monitor or focus state.
Scope {
  id: root
  property bool enabled: true
  property list<string> statusCommand: ["voxtype", "status", "--follow", "--format", "json"]
  property list<string> audioCommand: ["voxtype-audio-bridge"]
  property int statusRestartDelay: 2000
  property int audioRestartDelay: 1000
  property string state: "stopped"
  property bool audioConnected: false
  property real energy: 0
  property bool speechDetected: false
  readonly property bool active: recording || transcribing
  readonly property bool recording: state === "recording" || state === "streaming"
  readonly property bool transcribing: state === "transcribing"
  readonly property bool statusConnected: statusProcess.running
  property int frameIndex: 0
  readonly property var frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  readonly property string brailleFrame: frames[frameIndex]
  onRecordingChanged: if (!recording) resetAudio()
  onTranscribingChanged: frameIndex = 0
  onEnabledChanged: {
    statusRestart.stop(); audioRestart.stop();
    statusProcess.running = enabled; audioProcess.running = enabled;
    if (!enabled) { setState("stopped"); audioConnected = false; resetAudio(); }
  }

  function setState(nextState) {
    state = nextState === "recording" || nextState === "streaming" || nextState === "transcribing"
      ? nextState : nextState === "idle" ? "idle" : "stopped";
  }

  function parseStatus(line) {
    try {
      const status = JSON.parse(line);
      setState(status.alt || status.class || "stopped");
    } catch (error) {
      console.warn("Unable to parse VoxType status:", error);
    }
  }

  function resetAudio() {
    energy = 0;
    speechDetected = false;
  }

  function parseAudio(line) {
    const trimmed = (line || "").trim();
    if (trimmed.length === 0)
      return;

    try {
      const frame = JSON.parse(trimmed);
      if (frame.status === "connected") {
        audioConnected = true;
        return;
      }
      if (frame.status === "disconnected") {
        audioConnected = false;
        resetAudio();
        return;
      }
      if (!recording
          || typeof frame.peak !== "number"
          || typeof frame.rms !== "number"
          || !isFinite(frame.peak)
          || !isFinite(frame.rms))
        return;

      audioConnected = true;
      const peak = Math.max(0, Math.min(1, frame.peak));
      const rms = Math.max(0, Math.min(1, frame.rms));
      energy = Math.max(peak, rms);
      speechDetected = frame.vad === 1;
    } catch (error) {
      console.warn("Unable to parse VoxType audio frame:", error);
    }
  }

  Process {
    id: statusProcess
    command: root.statusCommand
    running: root.enabled
    stdout: SplitParser { onRead: data => root.parseStatus(data) }
    onExited: {
      root.setState("stopped");
      if (root.enabled) statusRestart.restart();
    }
  }
  Timer { id: statusRestart; interval: root.statusRestartDelay; onTriggered: if (root.enabled) statusProcess.running = true }
  Process {
    id: audioProcess
    command: root.audioCommand
    running: root.enabled
    stdout: SplitParser { onRead: data => root.parseAudio(data) }
    onExited: {
      root.audioConnected = false; root.resetAudio();
      if (root.enabled) audioRestart.restart();
    }
  }
  Timer { id: audioRestart; interval: root.audioRestartDelay; onTriggered: if (root.enabled) audioProcess.running = true }
  Timer { interval: 80; repeat: true; running: root.enabled && root.transcribing; onTriggered: root.frameIndex = (root.frameIndex + 1) % root.frames.length }
}
