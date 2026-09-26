import QtQuick
import Quickshell

// Presentation policy only. Domain controllers own devices, subprocesses and
// data; the messenger has a separate lifetime from this exclusive bar slot.
Scope {
  id: root
  required property var services
  required property var messenger
  property string focusedMonitor: ""
  property var monitors: []
  property string mode: "workspaces"
  property string targetMonitor: ""
  property string dictationTargetMonitor: ""
  property string microphoneFeedbackTargetMonitor: ""
  readonly property bool microphoneFeedbackActive: microphoneFeedback.running
  readonly property bool highlightFocusedWindow: mode !== "workspaces"
    || (messenger.visible && messenger.beeperData.viewFocused)
  readonly property bool systemProcessListsWanted: mode === "system" && !services.auth.active
    && !(services.dictation.active && dictationTargetMonitor === targetMonitor)
    && !(services.notifications.visible && services.notifications.targetMonitor === targetMonitor)
  property bool authRequestForUpdate: false
  property var authPreviousPanel: null

  function resolveMonitor(monitor = "") {
    return monitor || focusedMonitor || monitors[0] || "";
  }
  function isOpen(kind, monitor = "") {
    return mode === kind && (!monitor || targetMonitor === monitor);
  }
  function notificationCovers(monitor) {
    return services.notifications.visible
      && services.notifications.targetMonitor === monitor;
  }
  function canShareWithMessenger(kind) { return ["workspaces", "volume", "brightness"].includes(kind); }
  function messengerOpened() {
    if (messenger.visible && !canShareWithMessenger(mode)) close(mode);
  }
  Connections {
    target: root.messenger
    function onVisibleChanged() { root.messengerOpened(); }
    function onFocusSerialChanged() { root.messengerOpened(); }
  }
  function open(kind, monitor = "", restore = false) {
    if (!["workspaces", "volume", "brightness", "media", "audio", "calendar", "system",
          "wifi", "bluetooth", "updates", "launcher", "tabs"].includes(kind)) return;
    if (kind === "workspaces") { close(mode); return; }
    const target = resolveMonitor(monitor), previous = mode;
    if (notificationCovers(target)) services.notifications.close();
    if (previous === "calendar" && kind !== "calendar") services.calendar.weather.closeLocationSearch();
    // Native scan/password state is scoped to one presentation. Moving a
    // network picker to another monitor must finish its previous lifecycle.
    if (mode === kind && targetMonitor !== target && ["wifi", "bluetooth"].includes(kind))
      mode = "workspaces";
    targetMonitor = target;
    mode = kind;
    if (kind === "calendar") {
      if (previous !== "calendar" && !restore) {
        services.calendar.goToday();
        services.calendar.weather.beginCalendarSession();
      }
      services.calendar.weather.refreshIfNeeded();
    } else if (kind === "launcher") {
      if (previous !== "launcher") services.appLauncher.setQuery("");
      services.appLauncher.refreshResults();
    } else if (kind === "tabs") {
      services.chromeTabs.setQuery("");
      services.chromeTabs.selectedIndex = 0;
      services.chromeTabs.requestTabs();
    }
    // Resolve the destination layout before the messenger captures its return
    // geometry, so it morphs to this widget rather than a stale workspace pill.
    if (messenger.visible && !canShareWithMessenger(kind)) messenger.hide();
  }
  function close(kind) {
    if (mode !== kind) return;
    if (kind === "calendar") services.calendar.weather.closeLocationSearch();
    mode = "workspaces";
    targetMonitor = "";
  }
  function toggle(kind, monitor = "") {
    const target = resolveMonitor(monitor);
    if (isOpen(kind, target) && !notificationCovers(target)) close(kind);
    else open(kind, target);
  }
  function showVolume(monitor = "") {
    if (mode === "audio") return;
    open("volume", monitor);
    volumeTimeout.restart();
  }
  function showBrightness(monitor = "", refresh = true) {
    const target = resolveMonitor(monitor);
    open("brightness", target);
    brightnessTimeout.restart();
    if (refresh) services.brightness.queueChange(target, 0);
  }
  function brightnessUpdated(monitor) {
    if (isOpen("brightness", monitor)) brightnessTimeout.restart();
  }
  function brightnessFailed(monitor) {
    if (isOpen("brightness", monitor)) close("brightness");
  }
  function showMedia(monitor = "") {
    // Track changes are passive feedback, not a request to replace the chat.
    if (messenger.visible) return;
    if (!services.media.player || !["workspaces", "volume", "brightness", "media"].includes(mode)) return;
    open("media", monitor);
    mediaTimeout.restart();
  }
  function showMicrophoneFeedback(monitor = "") {
    microphoneFeedbackTargetMonitor = resolveMonitor(monitor);
    microphoneFeedback.restart();
  }
  function dictationChanged() {
    dictationTargetMonitor = services.dictation.active ? resolveMonitor() : "";
  }
  function beginAuthentication() {
    authRequestForUpdate = services.updates.awaitingPolkit;
    authPreviousPanel = authRequestForUpdate ? null : {mode: mode, monitor: targetMonitor};
    open("updates", resolveMonitor());
  }
  function finishAuthentication() {
    services.auth.clearInput();
    if (authRequestForUpdate) services.updates.awaitingPolkit = false;
    else if (authPreviousPanel) {
      const previous = authPreviousPanel;
      close("updates");
      if (monitors.includes(previous.monitor)) {
        if (previous.mode === "media") showMedia(previous.monitor);
        else if (!["workspaces", "volume", "brightness"].includes(previous.mode))
          open(previous.mode, previous.monitor, true);
      }
    }
    authPreviousPanel = null;
    authRequestForUpdate = false;
  }
  onMonitorsChanged: {
    if (services) services.brightness.reset();
    close("brightness");
    if (mode !== "workspaces" && !monitors.includes(targetMonitor)) close(mode);
    if (!monitors.includes(dictationTargetMonitor)) dictationTargetMonitor = "";
  }
  onModeChanged: {
    if (mode !== "volume") volumeTimeout.stop();
    if (mode !== "brightness") brightnessTimeout.stop();
    if (mode !== "media") mediaTimeout.stop();
  }
  Timer { id: volumeTimeout; interval: 2000; onTriggered: root.close("volume") }
  Timer { id: brightnessTimeout; interval: 2000; onTriggered: root.close("brightness") }
  Timer { id: mediaTimeout; interval: 4000; onTriggered: root.close("media") }
  Timer { id: microphoneFeedback; interval: 2000 }
}
