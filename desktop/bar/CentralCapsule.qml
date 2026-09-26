import QtQuick
import Local.LiquidGlass
import "../ui"
import "../ui/Theme.js" as Theme
import "../features/audio"
import "../features/brightness"
import "../features/calendar"
import "../features/dictation"
import "../features/launchers"
import "../features/network"
import "../features/notifications"
import "../features/system"
import "../features/updates"
import "../features/workspaces"

// Geometry and content crossfades only; panel lifetime belongs to ShellCoordinator.
Rectangle {
  id: root
  required property var services
  required property var coordinator
  required property var messengerHost
  required property string monitorName
  property var monitor: null
  property bool entered: false
  property real barTopInset: 10
  readonly property bool notificationActive: services.notifications.visible
    && monitorName === services.notifications.targetMonitor
  readonly property bool dictationOverlayActive: services.dictation.active
    && monitorName === coordinator.dictationTargetMonitor && !messengerHost.active
  readonly property bool volumeOverlayActive: coordinator.isOpen("volume", monitorName)
  readonly property bool audioSelectorActive: coordinator.isOpen("audio", monitorName)
  readonly property bool calendarActive: coordinator.isOpen("calendar", monitorName)
  readonly property bool systemPanelActive: coordinator.isOpen("system", monitorName)
  readonly property bool brightnessOverlayActive: coordinator.isOpen("brightness", monitorName)
  readonly property bool mediaOverlayActive: coordinator.isOpen("media", monitorName)
  readonly property bool wifiSelectorActive: coordinator.isOpen("wifi", monitorName)
  readonly property bool bluetoothSelectorActive: coordinator.isOpen("bluetooth", monitorName)
  readonly property bool updateSelectorActive: coordinator.isOpen("updates", monitorName)
  readonly property bool appLauncherActive: coordinator.isOpen("launcher", monitorName)
  readonly property bool chromeTabsActive: coordinator.isOpen("tabs", monitorName)
  readonly property bool audioSelectorKeyboardActive: audioSelectorActive && !services.dictation.active
  readonly property bool calendarKeyboardActive: calendarActive && !services.dictation.active
  readonly property bool systemPanelKeyboardActive: systemPanelActive && !services.dictation.active
  readonly property bool wifiSelectorKeyboardActive: wifiSelectorActive
  readonly property bool bluetoothSelectorKeyboardActive: bluetoothSelectorActive
  readonly property bool updateSelectorKeyboardActive: updateSelectorActive
  readonly property bool appLauncherKeyboardActive: appLauncherActive
  readonly property bool chromeTabsKeyboardActive: chromeTabsActive && !services.chromeTabs.actionPending
  readonly property bool keyboardSelectorActive: audioSelectorKeyboardActive || calendarKeyboardActive
    || systemPanelKeyboardActive || wifiSelectorKeyboardActive || bluetoothSelectorKeyboardActive
    || updateSelectorKeyboardActive || appLauncherKeyboardActive || chromeTabsKeyboardActive
  function restoreFocus() {
    if (!keyboardSelectorActive || notificationActive) return;
    const widget = ({audio: audioSelector, calendar: calendarPanel, system: systemPanel,
      wifi: wifiSelector, bluetooth: bluetoothSelector, updates: updateSelector,
      launcher: appLauncher, tabs: chromeTabsLauncher})[coordinator.mode];
    if (widget) widget.forceActiveFocus();
  }

  objectName: "centerMorph"
  z: 2
  GlassShape { objectName: "capsuleGlassShape"; anchors.fill: parent; radius: root.radius; enabled: GlassState.enabled && root.drawBackground }
  readonly property bool overlayVisible: root.notificationActive || root.volumeOverlayActive
    || root.audioSelectorActive || root.calendarActive || root.systemPanelActive
    || root.brightnessOverlayActive || root.mediaOverlayActive
    || root.appLauncherActive || root.chromeTabsActive
    || root.wifiSelectorActive || root.bluetoothSelectorActive
    || root.updateSelectorActive || root.dictationOverlayActive
  // The usual capsule yields its background to the chat morph. Temporary
  // widgets can still appear here, without touching the messenger state.
  property real overlayReveal: overlayVisible ? 1 : 0
  readonly property bool returningFromChat: root.messengerHost.presented && !root.messengerHost.active
  readonly property bool followingChatOpening: root.messengerHost.active && root.messengerHost.morphProgress < 1 && !overlayVisible
  // Exactly one material during handoff. Independent OSDs only have their own
  // glass while the chat is open, not while it transforms back into the bar.
  readonly property bool drawBackground: !root.messengerHost.presented || (root.messengerHost.active && overlayReveal > 0)
  Behavior on overlayReveal { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  readonly property string targetMode: root.notificationActive ? "notification"
    : root.dictationOverlayActive
    ? "dictation" : root.systemPanelActive ? "system"
    : root.calendarActive ? "calendar"
    : root.audioSelectorActive ? "audio"
    : root.appLauncherActive ? "launcher"
    : root.chromeTabsActive ? "tabs"
    : root.updateSelectorActive ? "updates"
    : root.wifiSelectorActive ? "wifi"
    : root.bluetoothSelectorActive ? "bluetooth"
    : root.mediaOverlayActive ? "media"
    : root.volumeOverlayActive ? "volume"
    : root.brightnessOverlayActive ? "brightness" : "workspaces"
  readonly property real preferredWidth: root.notificationActive
    ? notificationPopup.implicitWidth : root.dictationOverlayActive
    ? voiceDictationIndicator.implicitWidth
    : root.systemPanelActive ? workspaceSwitcher.expandedImplicitWidth
    : root.calendarActive ? workspaceSwitcher.expandedImplicitWidth
    : root.audioSelectorActive ? audioSelector.implicitWidth
    : root.appLauncherActive ? appLauncher.implicitWidth
    : root.chromeTabsActive ? chromeTabsLauncher.implicitWidth
    : root.updateSelectorActive ? updateSelector.implicitWidth
    : root.wifiSelectorActive ? wifiSelector.implicitWidth
    : root.bluetoothSelectorActive ? bluetoothSelector.implicitWidth
    : root.mediaOverlayActive ? nowPlayingIndicator.implicitWidth
    : overlayVisible ? 280 : workspaceSwitcher.implicitWidth
  readonly property real maximumWidth: workspaceSwitcher.expandedImplicitWidth
  readonly property real targetWidth: Math.min(preferredWidth, maximumWidth)
  readonly property real targetHeight: root.notificationActive
    ? notificationPopup.implicitHeight : root.dictationOverlayActive
    ? voiceDictationIndicator.implicitHeight
    : root.systemPanelActive ? systemPanel.implicitHeight
    : root.calendarActive ? calendarPanel.implicitHeight
    : root.audioSelectorActive ? audioSelector.implicitHeight
    : root.appLauncherActive ? appLauncher.implicitHeight
    : root.chromeTabsActive ? chromeTabsLauncher.implicitHeight
    : root.updateSelectorActive ? updateSelector.implicitHeight
    : root.wifiSelectorActive ? wifiSelector.implicitHeight : 36
  readonly property var contentModes: ["workspaces", "volume", "audio",
    "brightness", "dictation", "media", "wifi", "bluetooth",
    "launcher", "tabs", "updates", "notification", "calendar", "system"]
  property string visualSourceMode: "workspaces"
  property string visualTargetMode: "workspaces"
  property real transitionProgress: 1
  property real transitionDirection: 0
  property var startOpacities: ({ "workspaces": 1 })
  property var startOffsets: ({})

  function modeHeight(mode) {
    if (mode === "system") return systemPanel.implicitHeight;
    if (mode === "notification") return notificationPopup.implicitHeight;
    if (mode === "calendar") return calendarPanel.implicitHeight;
    if (mode === "audio") return audioSelector.implicitHeight;
    if (mode === "launcher") return appLauncher.implicitHeight;
    if (mode === "tabs") return chromeTabsLauncher.implicitHeight;
    if (mode === "updates") return updateSelector.implicitHeight;
    if (mode === "wifi") return wifiSelector.implicitHeight;
    if (mode === "bluetooth") return bluetoothSelector.implicitHeight;
    if (mode === "media") return nowPlayingIndicator.implicitHeight;
    if (mode === "volume") return volumeIndicator.implicitHeight;
    if (mode === "brightness") return brightnessIndicator.implicitHeight;
    if (mode === "dictation") return voiceDictationIndicator.implicitHeight;
    return workspaceSwitcher.implicitHeight;
  }

  // Coalesce synchronous state changes and follow the actually presented mode
  // on this monitor, including when a notification covers a changing widget.
  onTargetModeChanged: Qt.callLater(syncContentTransition)

  function syncContentTransition() {
    startContentTransition(visualTargetMode, targetMode);
  }

  function clamp01(value) {
    return Math.max(0, Math.min(1, value));
  }

  function smoothSegment(start, end, value) {
    const progress = clamp01((value - start) / (end - start));
    return progress * progress * (3 - 2 * progress);
  }

  function easeOutCubic(value) {
    const progress = clamp01(value);
    return 1 - Math.pow(1 - progress, 3);
  }

  function contentOpacity(mode) {
    // A hidden workspace row is not an outgoing OSD frame. Suppress it
    // before callLater starts the content transition as well as throughout
    // the OSD fade, including expiration while the chat is still open.
    if (mode === "workspaces" && (targetMode === "volume"
        || targetMode === "brightness" || targetMode === "notification"
        || root.messengerHost.originContentOpacity <= 0))
      return 0;
    const startOpacity = startOpacities[mode] === undefined
      ? 0 : startOpacities[mode];
    if (mode === visualTargetMode) {
      const entryProgress = smoothSegment(0.18, 0.78,
        transitionProgress);
      return startOpacity + (1 - startOpacity) * entryProgress;
    }
    const fadeEnd = mode === visualSourceMode ? 0.48 : 0.42;
    return startOpacity
      * (1 - smoothSegment(0, fadeEnd, transitionProgress));
  }

  function contentOffset(mode) {
    const startOffset = startOffsets[mode] === undefined
      ? 0 : startOffsets[mode];
    if (mode === visualSourceMode) {
      const exitProgress = easeOutCubic(transitionProgress / 0.58);
      const exitOffset = transitionDirection * 8;
      return startOffset + (exitOffset - startOffset) * exitProgress;
    }
    if (mode === visualTargetMode) {
      const entryProgress = easeOutCubic(
        (transitionProgress - 0.14) / 0.86);
      return startOffset * (1 - entryProgress);
    }
    return startOffset;
  }

  function startContentTransition(sourceMode, targetMode) {
    if (sourceMode === targetMode)
      return;

    const capturedOpacities = {};
    const capturedOffsets = {};
    for (let index = 0; index < contentModes.length; index++) {
      const mode = contentModes[index];
      capturedOpacities[mode] = contentOpacity(mode);
      capturedOffsets[mode] = contentOffset(mode);
    }

    contentTransition.stop();
    visualSourceMode = sourceMode;
    visualTargetMode = targetMode;
    const heightDelta = modeHeight(targetMode) - modeHeight(sourceMode);
    transitionDirection = heightDelta > 0 ? 1 : heightDelta < 0 ? -1 : 0;
    if (capturedOpacities[targetMode] <= 0.001)
      capturedOffsets[targetMode] = -transitionDirection * 10;
    startOpacities = capturedOpacities;
    startOffsets = capturedOffsets;
    transitionProgress = 0;
    contentTransition.restart();
  }

  anchors.horizontalCenter: parent.horizontalCenter
  y: root.barTopInset
  width: followingChatOpening ? root.messengerHost.capsuleWidth : targetWidth
  height: followingChatOpening ? root.messengerHost.capsuleHeight : targetHeight
  radius: 18
  color: !drawBackground ? "transparent" : GlassState.enabled ? Qt.alpha(Theme.background, 0.12) : Theme.background
  clip: true
  opacity: root.entered ? (returningFromChat ? root.messengerHost.originContentOpacity
    : Math.max(root.messengerHost.originContentOpacity, overlayReveal)) : 0
  visible: opacity > 0.001
  enabled: !root.messengerHost.active || overlayVisible

  Behavior on width {
    enabled: !root.messengerHost.presented
    NumberAnimation {
      duration: 360
      easing.type: Easing.OutCubic
    }
  }

  Behavior on height {
    enabled: !root.messengerHost.presented
    NumberAnimation {
      duration: 360
      easing.type: Easing.OutCubic
    }
  }

  NumberAnimation {
    id: contentTransition
    target: root
    property: "transitionProgress"
    from: 0
    to: 1
    duration: 360
    easing.type: Easing.Linear
  }

  transform: [
    Translate {
      y: root.entered ? 0 : -12
      Behavior on y {
        NumberAnimation {
          duration: 420
          easing.type: Easing.OutCubic
        }
      }
    },
    Translate {
      // The outgoing capsule content follows its expanding surface. OSDs
      // have their own background and always remain at the top-bar position.
      y: !root.drawBackground && root.messengerHost.presented
        ? root.messengerHost.surfaceItem.y - root.barTopInset : 0
    }
  ]

  WorkspaceSwitcher {
    id: workspaceSwitcher
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("workspaces") }
    backgroundColor: "transparent"
    monitor: root.monitor
    opacity: root.contentOpacity("workspaces")
    enabled: !root.overlayVisible
  }

  VolumeIndicator {
    id: volumeIndicator
    controller: root.services.audio
    onAdjustRequested: delta => { root.services.audio.setVolume(delta); root.coordinator.showVolume(root.monitorName); }
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("volume") }
    color: "transparent"
    opacity: root.contentOpacity("volume")
    enabled: root.volumeOverlayActive
  }

  AudioSelector {
    id: audioSelector
    controller: root.services.audio
    onCloseRequested: root.coordinator.close("audio")
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("audio") }
    opacity: root.contentOpacity("audio")
    enabled: root.audioSelectorKeyboardActive
  }

  BrightnessIndicator {
    id: brightnessIndicator
    controller: root.services.brightness
    onChangeRequested: delta => root.services.brightness.change(delta, root.monitorName)
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("brightness") }
    targetMonitor: root.monitorName
    color: "transparent"
    opacity: root.contentOpacity("brightness")
    enabled: root.brightnessOverlayActive
  }

  VoiceDictationIndicator {
    id: voiceDictationIndicator
    controller: root.services.dictation
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("dictation") }
    color: "transparent"
    opacity: root.contentOpacity("dictation")
    enabled: root.dictationOverlayActive
  }

  NowPlayingIndicator {
    id: nowPlayingIndicator
    controller: root.services.media
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("media") }
    opacity: root.contentOpacity("media")
    enabled: root.mediaOverlayActive
  }

  WifiSelector {
    id: wifiSelector
    controller: root.services.network
    spinnerFrame: root.services.spinner.frame
    onCloseRequested: root.coordinator.close("wifi")
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("wifi") }
    opacity: root.contentOpacity("wifi")
    enabled: root.wifiSelectorKeyboardActive
  }

  BluetoothSelector {
    id: bluetoothSelector
    controller: root.services.bluetooth
    spinnerFrame: root.services.spinner.frame
    onCloseRequested: root.coordinator.close("bluetooth")
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("bluetooth") }
    opacity: root.contentOpacity("bluetooth")
    enabled: root.bluetoothSelectorKeyboardActive
  }

  AppLauncher {
    id: appLauncher
    controller: root.services.appLauncher
    onCloseRequested: root.coordinator.close("launcher")
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("launcher") }
    opacity: root.contentOpacity("launcher")
    enabled: root.appLauncherKeyboardActive
  }

  ChromeTabsLauncher {
    id: chromeTabsLauncher
    controller: root.services.chromeTabs
    onCloseRequested: root.coordinator.close("tabs")
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("tabs") }
    opacity: root.contentOpacity("tabs")
    enabled: root.chromeTabsKeyboardActive
  }

  UpdateSelector {
    id: updateSelector
    updates: root.services.updates
    auth: root.services.auth
    spinnerFrame: root.services.spinner.frame
    onCloseRequested: root.coordinator.close("updates")
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
    }
    height: implicitHeight
    transform: Translate { y: root.contentOffset("updates") }
    opacity: root.contentOpacity("updates")
    enabled: root.updateSelectorKeyboardActive
  }

  SystemPanel {
    id: systemPanel
    telemetry: root.services.system.telemetry
    onCloseRequested: root.coordinator.close("system")
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    implicitWidth: workspaceSwitcher.expandedImplicitWidth
    height: implicitHeight
    transform: Translate { y: root.contentOffset("system") }
    opacity: root.contentOpacity("system")
    visible: opacity > 0
    enabled: root.systemPanelKeyboardActive
  }

  CalendarPanel {
    id: calendarPanel
    controller: root.services.calendar
    onCloseRequested: root.coordinator.close("calendar")
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    implicitWidth: workspaceSwitcher.expandedImplicitWidth
    height: implicitHeight
    transform: Translate { y: root.contentOffset("calendar") }
    opacity: root.contentOpacity("calendar")
    enabled: root.calendarKeyboardActive
  }

  NotificationInputGuard {
    id: notificationKeyboardShield
    anchors.fill: parent
    active: root.notificationActive
    captureInput: root.keyboardSelectorActive && !root.messengerHost.chatFocused
    z: 1
    onDismissed: root.services.notifications.close()
  }

  NotificationPopup {
    id: notificationPopup
    objectName: "barNotification"
    visible: root.services.notifications.presented !== null
    maximumWidth: workspaceSwitcher.expandedImplicitWidth
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: implicitHeight
    notificationData: root.services.notifications
    transform: Translate { y: root.contentOffset("notification") }
    opacity: root.contentOpacity("notification")
    enabled: root.notificationActive
    z: 2
  }
}
