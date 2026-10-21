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
  property var snapshot: null
  property var fitbitSnapshot: null
  property int fitbitMaxAgeMs: 6 * 60 * 60 * 1000
  property var transport: null
  property int generation: 0
  property bool initialized: false
  property bool configurationError: false
  readonly property bool configured: /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(serviceUuid)
    && serviceUuid !== "00000000-0000-0000-0000-000000000000"
  // Freshness of the PC monitor report is distinct from source measurement age.
  readonly property bool fresh: snapshot !== null && now - snapshot.receivedAt < staleAfterMs
    && snapshot.receivedAt <= now + 5000
  readonly property bool connected: fresh
  readonly property var percent: connected ? snapshot.phone.percent : null
  readonly property var pluggedIn: connected ? snapshot.phone.pluggedIn : null
  readonly property var charging: connected ? snapshot.phone.charging : null
  readonly property var updatedAt: connected ? snapshot.phone.updatedAt : null
  readonly property bool fitbitFresh: fitbitSnapshot !== null
    && now - fitbitSnapshot.updatedAt < fitbitMaxAgeMs && fitbitSnapshot.updatedAt <= now + 300000
  readonly property bool fitbitAvailable: connected && fitbitFresh
  readonly property var fitbitPercent: fitbitAvailable ? fitbitSnapshot.percent : null
  readonly property var fitbitUpdatedAt: fitbitAvailable ? fitbitSnapshot.updatedAt : null
  function invalidate() { snapshot = null; fitbitSnapshot = null; }
  function timestamp(value) { return Number.isSafeInteger(value) && value > 0; }
  function nullableBoolean(value) { return value === null || typeof value === "boolean"; }
  function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
  function level(value) { return value === null || Number.isInteger(value) && value >= 0 && value <= 100; }
  function accept(report) {
    if (!object(report) || report.event !== "relay" || report.mode !== "passive"
        || typeof report.available !== "boolean") { invalidate(); return false; }
    if (!report.available) { invalidate(); return true; }
    const phone = report.phone;
    if (!timestamp(report.receivedAt) || report.receivedAt > now + 5000
        || now - report.receivedAt >= staleAfterMs
        || !timestamp(report.observedAt) || report.observedAt > report.receivedAt + 5000
        || !object(phone) || !level(phone.percent) || !nullableBoolean(phone.pluggedIn)
        || !nullableBoolean(phone.charging) || !timestamp(phone.updatedAt)
        || phone.updatedAt > now + 300000) { invalidate(); return false; }
    // Atomic report of both sources; no preceding connection event or GATT state.
    snapshot = {mode: "passive", phone: {percent: phone.percent, pluggedIn: phone.pluggedIn,
      charging: phone.charging, updatedAt: phone.updatedAt}, observedAt: report.observedAt,
      receivedAt: report.receivedAt};
    const fitbit = report.fitbit;
    fitbitSnapshot = object(fitbit) && fitbit.percent !== null && level(fitbit.percent)
      && timestamp(fitbit.updatedAt) && fitbit.updatedAt <= now + 300000
      && now - fitbit.updatedAt < fitbitMaxAgeMs
      ? {percent: fitbit.percent, updatedAt: fitbit.updatedAt} : null;
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
    if (!initialized || !enabled || !configured || configurationError || transport !== null) return;
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
    stop(); configurationError = false; Qt.callLater(start);
  }
  function exited(process, sourceGeneration, exitCode) {
    if (process !== transport || sourceGeneration !== generation) return;
    transport = null;
    invalidate();
    process.destroy();
    configurationError = exitCode === 78;
    if (enabled && configured && !configurationError) retry.restart();
  }
  onEnabledChanged: reconfigure()
  onServiceUuidChanged: reconfigure()
  onCommandChanged: reconfigure()
  // Also expire after suspend, even when the process has not emitted EOF.
  // A fresh passive monitor report can restore the reading without a connection.
  onNowChanged: {
    if (snapshot !== null && !fresh) snapshot = null;
    if (fitbitSnapshot !== null && !fitbitFresh) fitbitSnapshot = null;
  }
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
            console.warn("Battery Relay:", line.slice(0, 512));
        }
      }
      onExited: (exitCode, exitStatus) => root.exited(receiver, runGeneration, exitCode)
    }
  }
}
