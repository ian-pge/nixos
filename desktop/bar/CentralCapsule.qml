import QtQuick
import Local.LiquidGlass
import "../ui"
import "../ui/Theme.js" as Theme
import "../ui/Morph.js" as Morph
import "../features/audio"
import "../features/brightness"
import "../features/calendar"
import "../features/dictation"
import "../features/launchers"
import "../features/network"
import "../features/notifications"
import "../features/system"
import "../features/storage"
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
  // Panel readability is independent of the number of workspace buttons.
  readonly property real panelWidth: 340
  readonly property bool notificationActive: services.notifications.visible
    && monitorName === services.notifications.targetMonitor
  readonly property bool dictationOverlayActive: services.dictation.active
    && monitorName === coordinator.dictationTargetMonitor && !messengerHost.active
  readonly property bool volumeOverlayActive: coordinator.isOpen("volume", monitorName)
  readonly property bool audioSelectorActive: coordinator.isOpen("audio", monitorName)
  readonly property bool calendarActive: coordinator.isOpen("calendar", monitorName)
  readonly property bool systemPanelActive: coordinator.isOpen("system", monitorName)
  readonly property bool storagePanelActive: coordinator.isOpen("storage", monitorName)
  readonly property bool brightnessOverlayActive: coordinator.isOpen("brightness", monitorName)
  readonly property bool mediaOverlayActive: coordinator.isOpen("media", monitorName)
  readonly property bool wifiSelectorActive: coordinator.isOpen("wifi", monitorName)
  readonly property bool bluetoothSelectorActive: coordinator.isOpen("bluetooth", monitorName)
  readonly property bool updateSelectorActive: coordinator.isOpen("updates", monitorName)
  readonly property bool appLauncherActive: coordinator.isOpen("launcher", monitorName)
  readonly property bool audioSelectorKeyboardActive: audioSelectorActive && !services.dictation.active
  readonly property bool calendarKeyboardActive: calendarActive && !services.dictation.active
  readonly property bool systemPanelKeyboardActive: systemPanelActive && !services.dictation.active
  readonly property bool storagePanelKeyboardActive: storagePanelActive && !services.dictation.active
  readonly property bool wifiSelectorKeyboardActive: wifiSelectorActive
  readonly property bool bluetoothSelectorKeyboardActive: bluetoothSelectorActive
  readonly property bool updateSelectorKeyboardActive: updateSelectorActive
  readonly property bool appLauncherKeyboardActive: appLauncherActive
  readonly property bool keyboardSelectorActive: audioSelectorKeyboardActive || calendarKeyboardActive
    || systemPanelKeyboardActive || storagePanelKeyboardActive
    || wifiSelectorKeyboardActive || bluetoothSelectorKeyboardActive
    || updateSelectorKeyboardActive || appLauncherKeyboardActive
  function restoreFocus() {
    if (!keyboardSelectorActive || notificationActive) return;
    const widget = ({audio: audioSelector, calendar: calendarPanel, system: systemPanel,
      storage: storagePanel, wifi: wifiSelector, bluetooth: bluetoothSelector, updates: updateSelector,
      launcher: appLauncher})[coordinator.mode];
    if (widget) widget.forceActiveFocus();
  }

  objectName: "centerMorph"
  z: 2
  GlassShape { objectName: "capsuleGlassShape"; anchors.fill: parent; radius: root.radius; enabled: GlassState.enabled && root.drawBackground }
  readonly property bool overlayVisible: root.notificationActive || root.volumeOverlayActive
    || root.audioSelectorActive || root.calendarActive || root.systemPanelActive || root.storagePanelActive
    || root.brightnessOverlayActive || root.mediaOverlayActive
    || root.appLauncherActive
    || root.wifiSelectorActive || root.bluetoothSelectorActive
    || root.updateSelectorActive || root.dictationOverlayActive
  // The usual capsule yields its background to the chat morph. Temporary
  // widgets can still appear here, without touching the messenger state.
  property real overlayReveal: overlayVisible ? 1 : 0
  property bool overlayDuringChat: false
  readonly property bool returningFromChat: root.messengerHost.presented && !root.messengerHost.active
  readonly property bool chatHandoff: root.messengerHost.presented && !drawBackground
  // Exactly one material during handoff. Independent OSDs only have their own
  // glass while the chat is open, not while it transforms back into the bar.
  readonly property bool drawBackground: !root.messengerHost.presented
    || (root.messengerHost.active && overlayDuringChat && overlayReveal > 0)
  Behavior on overlayReveal { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  onOverlayRevealChanged: if (!overlayVisible && overlayReveal === 0) overlayDuringChat = false
  readonly property string targetMode: root.notificationActive ? "notification"
    : root.dictationOverlayActive
    ? "dictation" : root.systemPanelActive ? "system"
    : root.storagePanelActive ? "storage"
    : root.calendarActive ? "calendar"
    : root.audioSelectorActive ? "audio"
    : root.appLauncherActive ? "launcher"
    : root.updateSelectorActive ? "updates"
    : root.wifiSelectorActive ? "wifi"
    : root.bluetoothSelectorActive ? "bluetooth"
    : root.mediaOverlayActive ? "media"
    : root.volumeOverlayActive ? "volume"
    : root.brightnessOverlayActive ? "brightness" : "workspaces"
  readonly property real preferredWidth: root.notificationActive
    ? notificationPopup.implicitWidth : root.dictationOverlayActive
    ? voiceDictationIndicator.implicitWidth
    : root.systemPanelActive ? maximumWidth
    : root.storagePanelActive ? maximumWidth
    : root.calendarActive ? maximumWidth
    : root.audioSelectorActive ? audioSelector.implicitWidth
    : root.appLauncherActive ? appLauncher.implicitWidth
    : root.updateSelectorActive ? updateSelector.implicitWidth
    : root.wifiSelectorActive ? wifiSelector.implicitWidth
    : root.bluetoothSelectorActive ? bluetoothSelector.implicitWidth
    : root.mediaOverlayActive ? nowPlayingIndicator.implicitWidth
    : root.volumeOverlayActive ? volumeIndicator.implicitWidth
    : root.brightnessOverlayActive ? brightnessIndicator.implicitWidth
    : workspaceSwitcher.implicitWidth
  readonly property real maximumWidth: Math.min(panelWidth, parent ? parent.width : panelWidth)
  readonly property real workspaceMaximumWidth: parent ? parent.width : workspaceSwitcher.implicitWidth
  readonly property real targetWidth: Math.min(preferredWidth,
    targetMode === "workspaces" ? workspaceMaximumWidth : maximumWidth)
  readonly property real targetHeight: root.notificationActive
    ? notificationPopup.implicitHeight : root.dictationOverlayActive
    ? voiceDictationIndicator.implicitHeight
    : root.systemPanelActive ? systemPanel.implicitHeight
    : root.storagePanelActive ? storagePanel.implicitHeight
    : root.calendarActive ? calendarPanel.implicitHeight
    : root.audioSelectorActive ? audioSelector.implicitHeight
    : root.appLauncherActive ? appLauncher.implicitHeight
    : root.updateSelectorActive ? updateSelector.implicitHeight
    : root.wifiSelectorActive ? wifiSelector.implicitHeight
    : root.bluetoothSelectorActive ? bluetoothSelector.implicitHeight
    : root.mediaOverlayActive ? nowPlayingIndicator.implicitHeight
    : root.volumeOverlayActive ? volumeIndicator.implicitHeight
    : root.brightnessOverlayActive ? brightnessIndicator.implicitHeight
    : workspaceSwitcher.implicitHeight
  readonly property var contentModes: ["workspaces", "volume", "audio",
    "brightness", "dictation", "media", "wifi", "bluetooth",
    "launcher", "updates", "notification", "calendar", "system", "storage"]
  readonly property var contentViews: ({workspaces: workspaceSwitcher, volume: volumeIndicator,
    audio: audioSelector, brightness: brightnessIndicator, dictation: voiceDictationIndicator,
    media: nowPlayingIndicator, wifi: wifiSelector, bluetooth: bluetoothSelector,
    launcher: appLauncher, updates: updateSelector,
    notification: notificationPopup, calendar: calendarPanel, system: systemPanel, storage: storagePanel})
  property string visualSourceMode: "workspaces"
  property string visualTargetMode: "workspaces"
  property real transitionProgress: 1
  property var startOpacities: ({ "workspaces": 1 })
  property var startLayoutWidths: ({})
  property var chatSourceOpacities: ({ "workspaces": 1 })
  property var chatSourceWidths: ({})
  property string chatSourceMode: "workspaces"

  function captureChatSource() {
    if (messengerHost.active) return;
    const weights = {}, widths = {};
    for (const mode of contentModes) {
      weights[mode] = contentOpacity(mode);
      widths[mode] = weights[mode] > 0.001 ? contentViews[mode].width : naturalContentWidth(mode);
    }
    chatSourceOpacities = weights;
    chatSourceWidths = widths;
    chatSourceMode = visualTargetMode;
    overlayDuringChat = ["volume", "brightness", "notification", "dictation"].includes(targetMode);
  }

  function settleContent(mode) {
    contentTransition.stop();
    visualSourceMode = mode; visualTargetMode = mode;
    startOpacities = ({ [mode]: 1 });
    startLayoutWidths = ({});
    transitionProgress = 1;
  }

  onReturningFromChatChanged: {
    if (!returningFromChat) return;
    // The incoming widget shares the chat's fade; do not fade it twice.
    // An interrupted opening retains whatever source content is still visible.
    if (messengerHost.originContentOpacity <= 0.001) settleContent(targetMode);
    else {
      contentTransition.stop();
      startOpacities = chatSourceOpacities;
      startLayoutWidths = chatSourceWidths;
      visualSourceMode = chatSourceMode; visualTargetMode = chatSourceMode;
      transitionProgress = 0;
      if (targetMode === chatSourceMode) contentTransition.restart();
      else startContentTransition(chatSourceMode, targetMode);
    }
  }

  onChatHandoffChanged: {
    if (chatHandoff) {
      // The messenger now owns the displayed geometry. Finish any previous
      // capsule resize off-screen so it cannot interfere with this handoff.
      capsuleWidthAnimation.complete();
      capsuleHeightAnimation.complete();
    }
    if (!chatHandoff && messengerHost.active) {
      // A separate volume/notification overlay must not revive the widget
      // that disappeared when the chat opened.
      contentTransition.stop();
      startOpacities = ({});
      startLayoutWidths = ({});
      visualSourceMode = targetMode; visualTargetMode = targetMode;
      transitionProgress = 0;
      contentTransition.restart();
    }
  }

  // Coalesce synchronous state changes and follow the actually presented mode
  // on this monitor, including when a notification covers a changing widget.
  onTargetModeChanged: {
    if (messengerHost.active && ["volume", "brightness", "notification", "dictation"].includes(targetMode))
      overlayDuringChat = true;
    Qt.callLater(syncContentTransition);
  }

  function syncContentTransition() {
    if (chatHandoff && messengerHost.active) return;
    startContentTransition(visualTargetMode, targetMode);
  }

  function contentOpacity(mode) {
    if (chatHandoff && messengerHost.active)
      return messengerHost.originContentOpacity > 0 ? (chatSourceOpacities[mode] || 0) : 0;
    // A hidden workspace row is not an outgoing OSD frame. Suppress it
    // before callLater starts the content transition as well as throughout
    // the OSD fade, including expiration while the chat is still open.
    if (mode === "workspaces" && (targetMode === "volume"
        || targetMode === "brightness" || targetMode === "notification"
        || root.messengerHost.originContentOpacity <= 0))
      return 0;
    const startOpacity = startOpacities[mode] === undefined
      ? 0 : startOpacities[mode];
    return mode === visualTargetMode ? Morph.incoming(startOpacity, transitionProgress)
      : Morph.outgoing(startOpacity, transitionProgress);
  }

  function naturalContentWidth(mode) {
    // A special workspace adds a slot to an already visible row. Follow that
    // slot's shared morph instead of instantly compressing all existing glyphs.
    return Math.min(mode === "workspaces" ? workspaceSwitcher.presentedImplicitWidth
      : contentViews[mode].implicitWidth,
      mode === "workspaces" ? workspaceMaximumWidth : maximumWidth);
  }

  function contentLayoutWidth(mode) {
    const natural = naturalContentWidth(mode);
    if (chatHandoff && messengerHost.active)
      return chatSourceWidths[mode] ?? natural;
    const start = startLayoutWidths[mode] ?? natural;
    // Keep layout independent of the animated surface on both axes, including
    // compact widgets. Resume an interrupted incoming view from its layout.
    return mode === visualTargetMode
      ? start + (natural - start) * Morph.easeOut(transitionProgress) : start;
  }

  function searchLayoutHeight(mode) {
    // Once open, resize only the viewport with the capsule's existing motion.
    // Filtering must not scale the text or shift the search field vertically.
    return !chatHandoff && targetMode === mode && visualTargetMode === mode
      && transitionProgress === 1 ? height : contentViews[mode].implicitHeight;
  }

  function startContentTransition(sourceMode, targetMode) {
    if (sourceMode === targetMode)
      return;

    const capturedOpacities = {}, capturedWidths = {};
    for (let index = 0; index < contentModes.length; index++) {
      const mode = contentModes[index];
      capturedOpacities[mode] = contentOpacity(mode);
      capturedWidths[mode] = capturedOpacities[mode] > 0.001
        ? contentViews[mode].width : naturalContentWidth(mode);
    }

    contentTransition.stop();
    visualSourceMode = sourceMode;
    visualTargetMode = targetMode;
    startOpacities = capturedOpacities;
    startLayoutWidths = capturedWidths;
    transitionProgress = 0;
    contentTransition.restart();
  }

  anchors.horizontalCenter: parent.horizontalCenter
  y: root.barTopInset
  // Animate the capsule's own destination, never the geometry borrowed from
  // the chat. A still-running Behavior must not overwrite the chat's frame.
  property real animatedWidth: targetWidth
  property real animatedHeight: targetHeight
  width: chatHandoff ? root.messengerHost.surfaceItem.width : animatedWidth
  height: chatHandoff ? root.messengerHost.surfaceItem.height : animatedHeight
  radius: Math.min(height / 2, Theme.barSize(18))
  color: !drawBackground ? "transparent" : GlassState.enabled ? Qt.alpha(Theme.background, 0.12) : Theme.background
  clip: true
  opacity: root.entered ? (chatHandoff ? root.messengerHost.originContentOpacity
    : Math.max(root.messengerHost.originContentOpacity, overlayReveal)) : 0
  visible: opacity > 0.001
  enabled: !root.messengerHost.active || overlayVisible

  Behavior on animatedWidth {
    enabled: !root.messengerHost.presented
    NumberAnimation {
      id: capsuleWidthAnimation
      duration: Morph.duration
      easing.type: Easing.OutCubic
    }
  }

  Behavior on animatedHeight {
    enabled: !root.messengerHost.presented
    NumberAnimation {
      id: capsuleHeightAnimation
      duration: Morph.duration
      easing.type: Easing.OutCubic
    }
  }

  NumberAnimation {
    id: contentTransition
    objectName: "capsuleContentTransition"
    target: root
    property: "transitionProgress"
    from: 0
    to: 1
    duration: Morph.duration
    easing.type: Easing.Linear
    onFinished: startLayoutWidths = ({})
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
    // Center every view arithmetically: anchor rounding causes small jumps
    // while the compact workspace row grows into a taller panel.
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("workspaces")
    height: implicitHeight
    transform: MorphScale { surface: root; content: workspaceSwitcher }
    backgroundColor: "transparent"
    monitor: root.monitor
    opacity: root.contentOpacity("workspaces")
    enabled: !root.overlayVisible
  }

  VolumeIndicator {
    id: volumeIndicator
    controller: root.services.audio
    onAdjustRequested: delta => { root.services.audio.setVolume(delta); root.coordinator.showVolume(root.monitorName); }
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("volume")
    height: implicitHeight
    transform: MorphScale { surface: root; content: volumeIndicator }
    color: "transparent"
    opacity: root.contentOpacity("volume")
    enabled: root.volumeOverlayActive
  }

  AudioSelector {
    id: audioSelector
    controller: root.services.audio
    onCloseRequested: root.coordinator.close("audio")
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("audio")
    height: implicitHeight
    transform: MorphScale { surface: root; content: audioSelector }
    opacity: root.contentOpacity("audio")
    enabled: root.audioSelectorKeyboardActive
  }

  BrightnessIndicator {
    id: brightnessIndicator
    controller: root.services.brightness
    onChangeRequested: delta => root.services.brightness.change(delta, root.monitorName)
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("brightness")
    height: implicitHeight
    transform: MorphScale { surface: root; content: brightnessIndicator }
    targetMonitor: root.monitorName
    color: "transparent"
    opacity: root.contentOpacity("brightness")
    enabled: root.brightnessOverlayActive
  }

  VoiceDictationIndicator {
    id: voiceDictationIndicator
    controller: root.services.dictation
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("dictation")
    height: implicitHeight
    transform: MorphScale { surface: root; content: voiceDictationIndicator }
    color: "transparent"
    opacity: root.contentOpacity("dictation")
    enabled: root.dictationOverlayActive
  }

  NowPlayingIndicator {
    id: nowPlayingIndicator
    controller: root.services.media
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("media")
    height: implicitHeight
    transform: MorphScale { surface: root; content: nowPlayingIndicator }
    opacity: root.contentOpacity("media")
    enabled: root.mediaOverlayActive
  }

  WifiSelector {
    id: wifiSelector
    controller: root.services.network
    spinnerFrame: root.services.spinner.frame
    onCloseRequested: root.coordinator.close("wifi")
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("wifi")
    height: implicitHeight
    transform: MorphScale { surface: root; content: wifiSelector }
    opacity: root.contentOpacity("wifi")
    enabled: root.wifiSelectorKeyboardActive
  }

  BluetoothSelector {
    id: bluetoothSelector
    controller: root.services.bluetooth
    spinnerFrame: root.services.spinner.frame
    onCloseRequested: root.coordinator.close("bluetooth")
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("bluetooth")
    height: implicitHeight
    transform: MorphScale { surface: root; content: bluetoothSelector }
    opacity: root.contentOpacity("bluetooth")
    enabled: root.bluetoothSelectorKeyboardActive
  }

  AppLauncher {
    id: appLauncher
    controller: root.services.appLauncher
    onCloseRequested: root.coordinator.close("launcher")
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.alignWhenCentered: false
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("launcher")
    height: root.searchLayoutHeight("launcher")
    transform: MorphScale { surface: root; content: appLauncher }
    opacity: root.contentOpacity("launcher")
    enabled: root.appLauncherKeyboardActive
  }

  UpdateSelector {
    id: updateSelector
    updates: root.services.updates
    auth: root.services.auth
    spinnerFrame: root.services.spinner.frame
    onCloseRequested: root.coordinator.close("updates")
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("updates")
    height: implicitHeight
    transform: MorphScale { surface: root; content: updateSelector }
    opacity: root.contentOpacity("updates")
    enabled: root.updateSelectorKeyboardActive
  }

  SystemPanel {
    id: systemPanel
    telemetry: root.services.system.telemetry
    onCloseRequested: root.coordinator.close("system")
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("system")
    implicitWidth: root.maximumWidth
    height: implicitHeight
    transform: MorphScale { surface: root; content: systemPanel }
    opacity: root.contentOpacity("system")
    visible: opacity > 0
    enabled: root.systemPanelKeyboardActive
  }

  StoragePanel {
    id: storagePanel
    objectName: "storagePanel"
    controller: root.services.storage
    onCloseRequested: root.coordinator.close("storage")
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("storage")
    implicitWidth: root.maximumWidth
    height: implicitHeight
    transform: MorphScale { surface: root; content: storagePanel }
    opacity: root.contentOpacity("storage")
    visible: opacity > 0
    enabled: root.storagePanelKeyboardActive
  }

  CalendarPanel {
    id: calendarPanel
    controller: root.services.calendar
    onCloseRequested: root.coordinator.close("calendar")
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("calendar")
    implicitWidth: root.maximumWidth
    height: implicitHeight
    transform: MorphScale { surface: root; content: calendarPanel }
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
    maximumWidth: root.maximumWidth
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: root.contentLayoutWidth("notification")
    height: implicitHeight
    notificationData: root.services.notifications
    transform: MorphScale { surface: root; content: notificationPopup }
    opacity: root.contentOpacity("notification")
    enabled: root.notificationActive
    z: 2
  }
}
