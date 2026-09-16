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
  property var manualLocation: null
  property bool locationSearchOpen: false
  property string locationQuery: ""
  property var locationResults: []
  property string locationSearchError: ""
  property string activeLocationQuery: ""
  property bool locationSearchPending: false
  property bool pendingRefresh: false
  readonly property bool searchingLocations: locationSearchPending || locationSearchProcess.running
  readonly property bool loading: weatherProcess.running || pendingRefresh
  readonly property real ageSeconds: snapshot === null ? Infinity
    : Math.max(0, clock.date.getTime() / 1000 - snapshot.updatedAt)
  readonly property bool usable: snapshot !== null && ageSeconds <= 86400
  readonly property bool stale: reportedStale || lastError !== "" || ageSeconds >= 3600
  readonly property var days: usable ? (snapshot?.days ?? ({})) : ({})
  readonly property string locationText: usable && snapshot !== null ? snapshot.location.name
    : manualLocation !== null ? manualLocation.name : "Localisation indisponible"
  readonly property string temperatureText: usable && typeof snapshot?.temperatureC === "number"
    && isFinite(snapshot.temperatureC) ? Math.round(snapshot.temperatureC) + "°" : "--°"
  readonly property string updateText: usable && snapshot !== null
    ? (stale ? "Cache " : "Màj ") + Qt.formatDateTime(new Date(snapshot.updatedAt * 1000), "dd/MM HH:mm")
    : loading ? "Actualisation…" : lastError || "Météo indisponible"

  function applyReport(line) {
    if (pendingRefresh)
      return;
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
    if (pendingRefresh) {
      refreshAfterLocationChange();
      return;
    }
    // Coalesce reopening and timer requests, including when offline.
    if (!weatherProcess.running && Date.now() - lastAttempt >= 60000)
      weatherProcess.running = true;
  }

  function beginCalendarSession() {
    // A search is temporary. Every real reopening redetects the current location.
    pendingRefresh = true;
    if (manualLocation !== null)
      snapshot = null;
    manualLocation = null;
    lastError = "";
    closeLocationSearch();
    Qt.callLater(refreshAfterLocationChange);
  }

  function openLocationSearch() {
    locationSearchOpen = true;
    setLocationQuery("");
  }

  function closeLocationSearch() {
    locationSearchOpen = false;
    locationDebounce.stop();
    locationSearchPending = false;
  }

  function setLocationQuery(query) {
    locationQuery = query;
    locationResults = [];
    locationSearchError = "";
    locationSearchPending = locationSearchOpen && query.trim().length >= 2;
    locationDebounce.stop();
    if (locationSearchPending)
      locationDebounce.restart();
  }

  function searchLocations() {
    if (!locationSearchOpen || locationQuery.trim().length < 2 || locationSearchProcess.running)
      return;
    activeLocationQuery = locationQuery.trim();
    locationSearchProcess.command = command.concat(["--search", activeLocationQuery]);
    locationSearchPending = false;
    locationSearchProcess.running = true;
  }

  function chooseLocation(location) {
    pendingRefresh = true;
    manualLocation = location;
    snapshot = null;
    lastError = "";
    locationSearchError = "";
    closeLocationSearch();
    Qt.callLater(refreshAfterLocationChange);
  }

  function refreshAfterLocationChange() {
    if (pendingRefresh && !weatherProcess.running) {
      pendingRefresh = false;
      weatherProcess.running = true;
    }
  }

  SystemClock { id: clock; precision: SystemClock.Minutes }

  Process {
    id: weatherProcess
    command: root.command.concat(root.manualLocation === null ? []
      : ["--location", JSON.stringify(root.manualLocation)])
    running: root.autoRefresh
    onRunningChanged: {
      if (running) {
        root.lastAttempt = Date.now();
        root.receivedReport = false;
      }
    }
    stdout: SplitParser { onRead: data => root.applyReport(data) }
    onExited: exitCode => {
      if (root.pendingRefresh)
        Qt.callLater(root.refreshAfterLocationChange);
      else if (exitCode !== 0 || !root.receivedReport)
        root.lastError = "Météo indisponible";
    }
  }

  Timer {
    id: locationDebounce
    interval: 350
    onTriggered: root.searchLocations()
  }

  Process {
    id: locationSearchProcess
    stdout: StdioCollector { id: locationSearchOutput }
    onExited: exitCode => {
      if (!root.locationSearchOpen)
        return;
      if (root.activeLocationQuery !== root.locationQuery.trim()) {
        if (!locationDebounce.running)
          Qt.callLater(root.searchLocations);
        return;
      }
      root.locationSearchPending = false;
      try {
        if (exitCode !== 0)
          throw new Error("Search failed");
        const report = JSON.parse(locationSearchOutput.text);
        if (!Array.isArray(report.results))
          throw new Error("Invalid search results");
        root.locationResults = report.results;
        root.locationSearchError = report.error || "";
      } catch (error) {
        root.locationSearchError = "Recherche de ville indisponible";
      }
    }
  }

  Timer {
    interval: 3600000
    running: root.autoRefresh
    repeat: true
    onTriggered: root.refresh()
  }
}
