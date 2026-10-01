import QtQuick
import Quickshell
import Quickshell.Io
import "StorageReport.js" as Report

// The privileged service publishes one atomic, aggregate-only report. Scans
// are shared across monitors and continue if the panel is closed meanwhile.
Scope {
  id: root
  property bool enabled: true
  property bool active: false
  property list<string> scanCommand: ["systemctl", "--no-ask-password", "start", "quickshell-storage.service"]
  property list<string> readCommand: ["cat", "/run/quickshell-storage/report.json"]
  property int minimumInterval: 60000
  property int cacheLifetime: 1800000
  property int timeout: 930000
  property var snapshot: null
  property string error: ""
  property string phase: "idle"
  property bool forceRequested: false
  property bool cancelled: false
  property bool readStarted: false
  property bool scanStarted: false
  property int generation: 0
  property real lastAttempt: 0
  property real scanStartedAt: 0
  property int scanCount: 0
  readonly property real updatedAt: snapshot?.measuredAt ?? 0
  readonly property real now: clock.date.getTime()
  readonly property bool loading: phase !== "idle"

  function refresh(force = false) {
    if (!enabled || loading || (lastAttempt > 0 && Date.now() - lastAttempt < minimumInterval)) return;
    if (!force && updatedAt > 0 && Date.now() - updatedAt < cacheLifetime) return;
    forceRequested = force;
    ++generation;
    cancelled = false;
    error = "";
    phase = "cached";
    readStarted = false;
    readProcess.running = true;
    deadline.restart();
  }
  function startScan() {
    if (!enabled || cancelled) { finish(); return; }
    phase = "scan";
    lastAttempt = Date.now();
    scanStartedAt = lastAttempt;
    ++scanCount;
    scanStarted = false;
    scanProcess.running = true;
  }
  function finish() {
    deadline.stop();
    phase = "idle";
  }
  function readFinished(code, text) {
    if (!enabled || cancelled || phase === "idle") return;
    const wasCached = phase === "cached";
    let accepted = false;
    if (code === 0) {
      try {
        const report = Report.parse(text, Date.now());
        if (report.measuredAt >= updatedAt
            && (wasCached || report.measuredAt >= scanStartedAt)) {
          snapshot = report;
          accepted = true;
        }
      } catch (_) { /* Keep the previous valid report while retrying. */ }
    }
    if (wasCached && (forceRequested || !accepted || Date.now() - updatedAt >= cacheLifetime)) {
      startScan();
    } else {
      if (!accepted) error = "Mesure indisponible · R pour réessayer";
      finish();
    }
  }
  function cancel() {
    cancelled = true;
    ++generation;
    readProcess.running = false;
    scanProcess.running = false;
    finish();
  }
  onActiveChanged: if (active) refresh()
  onEnabledChanged: {
    if (!enabled) cancel();
    else if (active) refresh();
  }
  Component.onCompleted: if (active) refresh()

  SystemClock { id: clock; precision: SystemClock.Minutes }
  Timer {
    id: deadline
    interval: root.timeout
    onTriggered: { root.error = "Analyse trop longue · R pour réessayer"; root.cancel(); }
  }
  Process {
    id: readProcess
    command: root.readCommand
    stdout: StdioCollector { id: reportText }
    stderr: StdioCollector {}
    onStarted: root.readStarted = true
    onExited: code => {
      const token = root.generation;
      Qt.callLater(() => {
        if (token === root.generation) root.readFinished(code, reportText.text);
      });
    }
    onRunningChanged: if (!running && !root.readStarted && root.loading)
      root.readFinished(1, "")
  }
  Process {
    id: scanProcess
    command: root.scanCommand
    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onStarted: root.scanStarted = true
    onExited: code => {
      if (root.cancelled || !root.enabled || root.phase !== "scan") return;
      if (code !== 0) {
        root.error = "Service de stockage indisponible · R pour réessayer";
        root.finish();
      } else {
        root.phase = "result";
        root.readStarted = false;
        readProcess.running = true;
      }
    }
    onRunningChanged: {
      if (running || root.scanStarted || root.cancelled || !root.enabled || root.phase !== "scan") return;
      root.error = "Service de stockage indisponible · R pour réessayer";
      root.finish();
    }
  }
}
