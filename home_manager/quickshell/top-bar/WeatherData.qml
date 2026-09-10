import Quickshell
import Quickshell.Io
import QtQuick

Scope {
  id: root

  property list<string> command: ["quickshell-weather"]
  property bool autoRefresh: true
  property var snapshot: null
  property string lastError: ""
  property bool reportedStale: false
  property real lastAttempt: 0
  property bool receivedReport: false
  readonly property bool loading: weatherProcess.running
  readonly property real ageSeconds: snapshot === null ? Infinity
    : Math.max(0, clock.date.getTime() / 1000 - snapshot.updatedAt)
  readonly property bool usable: snapshot !== null && ageSeconds <= 86400
  readonly property bool stale: reportedStale || lastError !== "" || ageSeconds >= 3600
  readonly property var days: usable ? snapshot.days : ({})
  readonly property string locationText: usable ? snapshot.location.name : "Localisation indisponible"
  readonly property string temperatureText: usable && typeof snapshot.temperatureC === "number"
    && isFinite(snapshot.temperatureC) ? Math.round(snapshot.temperatureC) + "°" : "--°"
  readonly property string updateText: usable
    ? (stale ? "Cache " : "Màj ") + Qt.formatDateTime(new Date(snapshot.updatedAt * 1000), "dd/MM HH:mm")
    : loading ? "Actualisation…" : lastError || "Météo indisponible"

  function applyReport(line) {
    try {
      const report = JSON.parse(line);
      if (typeof report.stale !== "boolean" || !("data" in report))
        throw new Error("Invalid weather report");
      const data = report.data;
      if (data !== null && (data.version !== 2 || typeof data.updatedAt !== "number"
          || !isFinite(data.updatedAt) || data.updatedAt > Date.now() / 1000 + 60
          || typeof data.location?.name !== "string" || typeof data.days !== "object"
          || data.days === null || Array.isArray(data.days)))
        throw new Error("Invalid weather snapshot");
      if (data !== null)
        snapshot = data;
      reportedStale = report.stale;
      lastError = typeof report.error === "string" ? report.error : "";
      receivedReport = true;
    } catch (error) {
      lastError = "Météo indisponible";
      console.warn("Unable to parse weather data:", error);
    }
  }

  function refreshIfNeeded() {
    if (!usable || stale)
      refresh();
  }

  function refresh() {
    // Coalesce reopening and timer requests, including when offline.
    if (!weatherProcess.running && Date.now() - lastAttempt >= 60000)
      weatherProcess.running = true;
  }

  SystemClock { id: clock; precision: SystemClock.Minutes }

  Process {
    id: weatherProcess
    command: root.command
    running: root.autoRefresh
    onRunningChanged: {
      if (running) {
        root.lastAttempt = Date.now();
        root.receivedReport = false;
      }
    }
    stdout: SplitParser { onRead: data => root.applyReport(data) }
    onExited: exitCode => {
      if (exitCode !== 0 || !root.receivedReport)
        root.lastError = "Météo indisponible";
    }
  }

  Timer {
    interval: 3600000
    running: root.autoRefresh
    repeat: true
    onTriggered: root.refresh()
  }
}
