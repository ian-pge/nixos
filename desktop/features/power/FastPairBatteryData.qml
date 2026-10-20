import Quickshell
import Quickshell.Io
import QtQuick

// One connection-free receiver for the whole shell. Never reads key contents.
Scope {
  id: root
  property bool enabled: true
  property string keyFile: Quickshell.env("QS_EARBUDS_ACCOUNT_KEY_FILE")
    || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
      + "/battery-relay/pixel-buds.account-key")
  property list<string> command: ["fast-pair-battery"]
  property int staleAfterMs: 180000
  property int restartDelay: 5000
  property real now: clock.date.getTime()
  property var snapshot: null
  property var transport: null
  property int generation: 0
  property bool initialized: false
  property bool configurationError: false
  readonly property bool configured: keyFile.startsWith("/") && !keyFile.startsWith("/nix/store/")
  readonly property bool fresh: snapshot !== null
    && now - snapshot.receivedAt < staleAfterMs && snapshot.receivedAt <= now + 5000
    && now - snapshot.observedAt < staleAfterMs && snapshot.observedAt <= now + 5000
  readonly property bool available: fresh

  function invalidate() { snapshot = null; }
  function timestamp(value) { return Number.isSafeInteger(value) && value > 0; }
  function level(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
      && (value.percent === null || Number.isInteger(value.percent) && value.percent >= 0 && value.percent <= 100)
      && (value.charging === null || typeof value.charging === "boolean");
  }
  function accept(report) {
    if (report === null || typeof report !== "object" || Array.isArray(report)) {
      invalidate(); return false;
    }
    const parts = [report.case, report.left, report.right];
    if (report.event !== "earbuds" || typeof report.available !== "boolean"
        || !parts.every(level) || !timestamp(report.receivedAt)
        || report.receivedAt > now + 5000 || now - report.receivedAt >= staleAfterMs
        || (report.available
          ? !timestamp(report.observedAt) || report.observedAt > now + 5000
            || now - report.observedAt >= staleAfterMs || !parts.some(value => value.percent !== null)
          : report.observedAt !== null || parts.some(value => value.percent !== null || value.charging !== null))) {
      invalidate(); return false;
    }
    snapshot = report.available ? {
      case: {percent: report.case.percent, charging: report.case.charging},
      left: {percent: report.left.percent, charging: report.left.charging},
      right: {percent: report.right.percent, charging: report.right.charging},
      observedAt: report.observedAt, receivedAt: report.receivedAt
    } : null;
    return true;
  }
  function acceptLine(line) {
    try {
      if (line.length > 4096) throw new Error("Oversized Fast Pair report");
      return accept(JSON.parse(line));
    } catch (error) { invalidate(); console.warn("Invalid Fast Pair report:", error.message); return false; }
  }
  function receive(line, runGeneration) {
    if (runGeneration !== generation || !enabled || !configured) return;
    acceptLine(line);
  }
  function start() {
    if (!initialized || !enabled || !configured || configurationError || transport !== null) return;
    ++generation; invalidate();
    transport = receiverComponent.createObject(root, {
      command: command.concat(["--key-file", keyFile]), runGeneration: generation
    });
    if (transport !== null) transport.running = true;
    else retry.restart();
  }
  function stop() {
    retry.stop(); ++generation;
    const old = transport; transport = null; invalidate();
    if (old !== null) { old.running = false; old.destroy(); }
  }
  function reconfigure() {
    if (!initialized) return;
    stop(); configurationError = false; Qt.callLater(start);
  }
  function exited(process, runGeneration, exitCode) {
    if (process !== transport || runGeneration !== generation) return;
    transport = null; invalidate(); process.destroy();
    configurationError = exitCode === 78;
    if (enabled && configured && !configurationError) retry.restart();
  }
  onEnabledChanged: reconfigure()
  onKeyFileChanged: reconfigure()
  onCommandChanged: reconfigure()
  onNowChanged: if (snapshot !== null && !fresh) invalidate()
  Component.onCompleted: { initialized = true; start(); }
  Component.onDestruction: if (transport !== null) transport.running = false
  SystemClock { id: clock; precision: SystemClock.Seconds }
  Timer { id: retry; interval: root.restartDelay; onTriggered: root.start() }
  Component {
    id: receiverComponent
    Process {
      id: receiver
      property int runGeneration: 0
      stdout: SplitParser { onRead: line => root.receive(line, receiver.runGeneration) }
      stderr: SplitParser {
        onRead: line => {
          if (receiver.runGeneration === root.generation && line.length)
            console.warn("Fast Pair battery:", line.slice(0, 512));
        }
      }
      onExited: (exitCode, exitStatus) => root.exited(receiver, receiver.runGeneration, exitCode)
    }
  }
}
