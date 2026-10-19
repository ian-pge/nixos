import Quickshell
import Quickshell.Io
import QtQuick

// One receiver per shell, independent of monitor count. No fallback provider.
Scope {
  id: root
  property bool enabled: true
  property string serviceUuid: Quickshell.env("QS_PHONE_BATTERY_SERVICE_UUID") || ""
  property list<string> command: ["battery-relay-receiver"]
  property int restartDelay: 5000
  property int staleAfterMs: 180000
  property real now: clock.date.getTime()
  property bool reportedConnected: false
  property var snapshot: null
  property var transport: null
  property int generation: 0
  property bool initialized: false
  readonly property bool configured: /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(serviceUuid)
    && serviceUuid !== "00000000-0000-0000-0000-000000000000"
  readonly property bool fresh: snapshot !== null && now - snapshot.receivedAt < staleAfterMs
    && snapshot.receivedAt <= now + 5000
  readonly property bool connected: reportedConnected && fresh
  readonly property var percent: connected ? (snapshot?.percent ?? null) : null
  readonly property var pluggedIn: connected ? (snapshot?.pluggedIn ?? null) : null
  readonly property var charging: connected ? (snapshot?.charging ?? null) : null
  readonly property var updatedAt: connected ? (snapshot?.updatedAt ?? null) : null

  function invalidate() { reportedConnected = false; snapshot = null; }
  function timestamp(value) { return Number.isSafeInteger(value) && value > 0; }
  function nullableBoolean(value) { return value === null || typeof value === "boolean"; }
  function accept(report) {
    if (report === null || typeof report !== "object" || Array.isArray(report)) {
      invalidate(); return false;
    }
    if (report.event === "connection" && typeof report.connected === "boolean") {
      if (!report.connected) invalidate();
      else reportedConnected = true;
      return true;
    }
    // Reserved future devices cannot establish or extend the phone session.
    if (report.event === "battery" && report.device !== "phone") return false;
    if (report.event !== "battery" || !reportedConnected
        || !(report.percent === null || Number.isInteger(report.percent) && report.percent >= 0 && report.percent <= 100)
        || !nullableBoolean(report.pluggedIn) || !nullableBoolean(report.charging)
        || !timestamp(report.updatedAt) || !timestamp(report.receivedAt)
        || report.receivedAt > now + 5000 || now - report.receivedAt >= staleAfterMs) {
      invalidate(); return false;
    }
    // receivedAt is the PC clock; updatedAt is the phone clock and can differ.
    snapshot = {percent: report.percent, pluggedIn: report.pluggedIn, charging: report.charging,
      updatedAt: report.updatedAt, receivedAt: report.receivedAt};
    return true;
  }
  function acceptLine(line) {
    try {
      if (line.length > 4096) throw new Error("Oversized battery report");
      return accept(JSON.parse(line));
    } catch (error) {
      invalidate(); console.warn("Invalid Battery Relay report:", error.message); return false;
    }
  }
  function receive(line, sourceGeneration) {
    if (sourceGeneration !== generation || !enabled || !configured) return;
    acceptLine(line);
  }
  function start() {
    if (!initialized || !enabled || !configured || transport !== null) return;
    ++generation;
    invalidate();
    transport = receiverComponent.createObject(root, {
      command: command.concat(["--service", serviceUuid]), runGeneration: generation
    });
    if (transport !== null) transport.running = true;
    else retry.restart();
  }
  function stop() {
    retry.stop();
    ++generation;
    const old = transport;
    transport = null;
    invalidate();
    if (old !== null) { old.running = false; old.destroy(); }
  }
  function reconfigure() {
    if (!initialized) return;
    stop(); Qt.callLater(start);
  }
  function exited(process, sourceGeneration) {
    if (process !== transport || sourceGeneration !== generation) return;
    transport = null;
    invalidate();
    process.destroy();
    if (enabled && configured) retry.restart();
  }
  onEnabledChanged: reconfigure()
  onServiceUuidChanged: reconfigure()
  onCommandChanged: reconfigure()
  // Also expire after suspend, even when the process has not emitted EOF.
  // Keep the transport state so a fresh heartbeat can restore the reading.
  onNowChanged: if (snapshot !== null && !fresh) snapshot = null
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
      onExited: root.exited(receiver, runGeneration)
    }
  }
}
