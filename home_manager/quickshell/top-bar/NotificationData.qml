import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Scope {
  id: root

  property var current: null
  property var presented: null
  property string targetMonitor: ""
  readonly property bool visible: current !== null
  readonly property var targetOutput: Hyprland.monitors.values.find(
    monitor => monitor.name === targetMonitor) ?? null
  readonly property bool targetBlocked: targetOutput === null
    || (targetOutput.activeWorkspace !== null
      && targetOutput.activeWorkspace.hasFullscreen)
  property bool escapeSyncPending: false
  // Nix pins the player and the unmodified theme sound to store paths.
  property string soundPlayer: "pw-play"

  // Keep the native image alive until the closing animation has finished.
  RetainableLock {
    object: root.presented
    locked: true
  }

  NotificationServer {
    keepOnReload: false
    actionsSupported: true
    bodySupported: true
    imageSupported: true
    persistenceSupported: false
    bodyMarkupSupported: false
    inlineReplySupported: false
    onNotification: notification => root.receive(notification)
  }

  function receive(notification) {
    notification.tracked = true;
    const monitor = Hyprland.focusedMonitor
      ?? Hyprland.monitors.values[0] ?? null;
    if (monitor === null || (monitor.activeWorkspace !== null
        && monitor.activeWorkspace.hasFullscreen)) {
      notification.expire();
      return;
    }
    const previous = current;
    releaseTimer.stop();
    current = notification;
    presented = notification;
    targetMonitor = monitor.name;
    refreshPresentation();
    if (previous !== null && previous !== notification)
      previous.expire();
    playSound(notification);
  }

  function playSound(notification) {
    if (notification.hints["suppress-sound"])
      return;
    // Independent one-shot players: no cooldown, queue or dropped burst sounds.
    // Only new arrivals play; updating an existing card must not replay its sound.
    Quickshell.execDetached([soundPlayer, "--media-role", "Notification", "--volume", "2.0",
      "/run/current-system/sw/share/sounds/freedesktop/stereo/message-new-instant.oga"]);
  }

  function refreshPresentation() {
    if (!visible)
      return;
    lifetime.restart();
    syncEscape();
  }

  function clear() {
    lifetime.stop();
    current = null;
    releaseTimer.restart();
    syncEscape();
  }

  function close(expired = false) {
    const notification = current;
    if (notification === null)
      return;
    clear();
    if (expired)
      notification.expire();
    else
      notification.dismiss();
  }

  function activate() {
    const notification = current;
    if (notification === null)
      return;
    const action = notification.actions.find(action => action.identifier === "default");
    if (!action)
      return;
    action.invoke();
    // Non-resident notifications may have closed synchronously during invoke().
    if (current === notification)
      close();
  }

  function syncEscape() {
    if (escapeSync.running) {
      escapeSyncPending = true;
      return;
    }
    escapeSyncPending = false;
    // A short lease also releases Escape if Quickshell exits unexpectedly.
    escapeSync.command = ["hyprctl", "eval",
      "quickshell_notification_deadline = " + (visible ? "os.time() + 5" : "0")];
    escapeSync.running = true;
  }

  onTargetBlockedChanged: {
    if (visible && targetBlocked)
      close(true);
  }

  Connections {
    target: root.current
    function onClosed(reason) { root.clear(); }
    // Replacements can update the existing native notification in place.
    function onSummaryChanged() { Qt.callLater(root.refreshPresentation); }
    function onBodyChanged() { Qt.callLater(root.refreshPresentation); }
    function onImageChanged() { Qt.callLater(root.refreshPresentation); }
  }

  Timer {
    id: lifetime
    interval: 360 + 3000
    onTriggered: root.close(true)
  }

  Timer {
    id: releaseTimer
    interval: 360
    onTriggered: {
      root.presented = null;
      root.targetMonitor = "";
    }
  }

  Process {
    id: escapeSync
    onRunningChanged: {
      if (!running && root.escapeSyncPending)
        Qt.callLater(root.syncEscape);
    }
  }

  Component.onCompleted: syncEscape()
  Component.onDestruction: Quickshell.execDetached([
    "hyprctl", "eval", "quickshell_notification_deadline = 0"])
}
