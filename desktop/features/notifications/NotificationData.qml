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
  property bool suppressNativeBeeper: false
  property bool suppressChatBanners: false
  property var monitors: Hyprland.monitors.values
  property var focusedMonitor: Hyprland.focusedMonitor
  readonly property bool visible: current !== null
  readonly property var targetOutput: monitors.find(
    monitor => monitor.name === targetMonitor) ?? null
  readonly property bool targetBlocked: targetOutput === null
  property bool escapeSyncPending: false
  property alias doNotDisturb: preferences.doNotDisturb
  readonly property bool dndFeedbackActive: dndFeedback.running
  property string dndFeedbackTargetMonitor: ""
  property var soundProcesses: []
  // Nix pins the player and the unmodified theme sound to store paths.
  property string soundPlayer: "pw-play"

  PersistentProperties {
    id: preferences
    reloadableId: "notificationPreferences"
    property bool doNotDisturb: false
  }

  function toggleDoNotDisturb(targetMonitor = "") {
    const monitor = focusedMonitor ?? monitors[0] ?? null;
    dndFeedbackTargetMonitor = targetMonitor !== ""
      ? targetMonitor : monitor !== null ? monitor.name : "";
    doNotDisturb = !doNotDisturb;
    dndFeedback.restart();
  }

  onDoNotDisturbChanged: {
    if (doNotDisturb) {
      close(true);
      // Stop only our notification sounds, never other application audio.
      soundProcesses.slice().forEach(player => player.running = false);
    }
  }
  onSuppressChatBannersChanged: {
    if (!suppressChatBanners) return;
    if (current !== null && isChatNotification(current)) close(true);
    // Opening the messenger also removes a chat card already fading out.
    if (presented !== null && isChatNotification(presented)) {
      releaseTimer.stop(); presented = null;
      if (current === null) targetMonitor = "";
    }
  }

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

  function isNativeBeeper(notification) {
    const desktopEntry = notification.hints?.["desktop-entry"] || "";
    return notification.appName === "Beeper" || desktopEntry === "beeper"
      || desktopEntry === "Beeper" || desktopEntry === "com.automattic.beeper.desktop";
  }
  function isChatNotification(notification) {
    const category = String(notification.hints?.category || "");
    return notification.hints?.["desktop-entry"] === "quickshell-beeper"
      || isNativeBeeper(notification) || category === "im" || category.startsWith("im.");
  }
  function receive(notification) {
    notification.tracked = true;
    // Only suppress the original Desktop client once our API consumer is
    // connected. Our producer has its own Messages/quickshell-beeper identity.
    if (suppressNativeBeeper && isNativeBeeper(notification)) {
      notification.expire();
      return;
    }
    // Discard immediately, including critical notifications; no deferred queue.
    if (doNotDisturb) {
      notification.expire();
      return;
    }
    if (suppressChatBanners && isChatNotification(notification)) {
      playSound(notification);
      notification.expire();
      return;
    }
    const monitor = focusedMonitor ?? monitors[0] ?? null;
    if (monitor === null) {
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
    if (doNotDisturb || notification.hints["suppress-sound"])
      return;
    // Independent one-shot players: no cooldown, queue or dropped burst sounds.
    // Only new arrivals play; updating an existing card must not replay its sound.
    const player = soundProcess.createObject(root, {
      command: [soundPlayer, "--media-role", "Notification", "--volume", "2.0",
        "/run/current-system/sw/share/sounds/freedesktop/stereo/message-new-instant.oga"]
    });
    soundProcesses = soundProcesses.concat([player]);
    player.running = true;
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
    id: dndFeedback
    interval: 2000
  }

  Component {
    id: soundProcess
    Process {
      id: player
      onRunningChanged: {
        if (!running) {
          root.soundProcesses = root.soundProcesses.filter(item => item !== player);
          player.destroy();
        }
      }
    }
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
