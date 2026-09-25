import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import Local.LiquidGlass
import "components"
import "components/Calendar.js" as Calendar
import "components/Theme.js" as Theme

PanelWindow {
  id: window

  required property var modelData
  required property var statusData

  property bool entered: false
  property bool beeperNativeDialogOpen: false
  readonly property bool beeperActive: statusData.beeperVisible
    && monitorName === statusData.beeperTargetMonitor
  readonly property bool beeperNotificationActive: beeperActive
    && statusData.notifications.visible
    && monitorName === statusData.notifications.targetMonitor
  readonly property bool beeperDictationActive: beeperActive
    && statusData.voiceDictationActive
    && monitorName === statusData.voiceDictationTargetMonitor
  readonly property int barTopInset: 10
  readonly property real beeperWorkAreaTop: exclusiveZone
  readonly property real beeperWorkAreaHeight: Math.max(0, height - beeperWorkAreaTop)
  readonly property real beeperPanelHeight: Math.min(900, Math.max(0, beeperWorkAreaHeight - 128))
  readonly property var hyprlandMonitor: Hyprland.monitorFor(window.screen)
    ?? Hyprland.monitors.values.find(monitor => monitor.name === window.modelData.name)
    ?? null
  readonly property string monitorName: hyprlandMonitor !== null
    ? hyprlandMonitor.name : ""
  readonly property bool fullscreenActive: hyprlandMonitor !== null
    && hyprlandMonitor.activeWorkspace !== null
    && hyprlandMonitor.activeWorkspace.hasFullscreen
  readonly property bool notificationActive: statusData.notifications.visible
    && monitorName === statusData.notifications.targetMonitor
    && !beeperActive
  readonly property bool volumeOverlayActive: statusData.volumeOverlayVisible
    && monitorName === statusData.volumeTargetMonitor
  readonly property bool audioSelectorActive: statusData.audioSelectorVisible
    && monitorName === statusData.audioTargetMonitor
  readonly property bool audioSelectorKeyboardActive: audioSelectorActive
    && !statusData.voiceDictationActive
  readonly property bool calendarActive: statusData.calendarVisible
    && monitorName === statusData.calendarTargetMonitor
  readonly property bool calendarKeyboardActive: calendarActive
    && !statusData.voiceDictationActive
  readonly property bool systemPanelActive: statusData.systemPanelVisible
    && monitorName === statusData.systemTargetMonitor
  readonly property bool systemPanelKeyboardActive: systemPanelActive
    && !statusData.voiceDictationActive
  readonly property bool brightnessOverlayActive: statusData.brightnessOverlayVisible
    && monitorName === statusData.brightnessTargetMonitor
  readonly property bool dictationOverlayActive: statusData.voiceDictationActive
    && monitorName === statusData.voiceDictationTargetMonitor
    && !beeperActive
  readonly property bool mediaOverlayActive: statusData.mediaOverlayVisible
    && monitorName === statusData.mediaTargetMonitor
  readonly property bool wifiSelectorActive: statusData.wifiSelectorVisible
    && monitorName === statusData.wifiTargetMonitor
  readonly property bool bluetoothSelectorActive: statusData.bluetoothSelectorVisible
    && monitorName === statusData.bluetoothTargetMonitor
  readonly property bool updateSelectorActive: statusData.updateSelectorVisible
    && monitorName === statusData.updateTargetMonitor
  readonly property bool appLauncherActive: statusData.appLauncherVisible
    && monitorName === statusData.appLauncherTargetMonitor
  readonly property bool chromeTabsActive: statusData.chromeTabsVisible
    && monitorName === statusData.chromeTabsTargetMonitor
  readonly property bool wifiSelectorKeyboardActive: wifiSelectorActive
  readonly property bool bluetoothSelectorKeyboardActive: bluetoothSelectorActive
  readonly property bool updateSelectorKeyboardActive: updateSelectorActive
  readonly property bool appLauncherKeyboardActive: appLauncherActive
  readonly property bool chromeTabsKeyboardActive: chromeTabsActive
    && !statusData.chromeTabsActionPending
  readonly property bool keyboardSelectorActive: wifiSelectorKeyboardActive
    || bluetoothSelectorKeyboardActive || updateSelectorKeyboardActive
    || appLauncherKeyboardActive || chromeTabsKeyboardActive || audioSelectorKeyboardActive
    || calendarKeyboardActive || systemPanelKeyboardActive

  screen: modelData

  anchors {
    top: true
    left: true
    right: true
  }

  margins {
    top: 0
    left: 5
    right: 5
  }

  // Keep the layer surface geometry fixed so expanding the update card cannot
  // nudge the other bar modules. The mask leaves the unused area click-through.
  // Include the space above the bar so upward bounces are not clipped.
  implicitHeight: screen.height
  color: "transparent"
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 36 + barTopInset
  // Raise this monitor's entire bar while a central widget is open. Keep it
  // above fullscreen through the closing morph, then return to the normal layer.
  WlrLayershell.layer: fullscreenActive
    && (centerMorph.overlayVisible || fullscreenHideDelay.running)
    ? WlrLayer.Overlay : WlrLayer.Top
  WlrLayershell.namespace: "quickshell-top-bar"
  WlrLayershell.keyboardFocus: keyboardSelectorActive
    ? WlrKeyboardFocus.Exclusive : beeperActive && !beeperNativeDialogOpen
    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  HyprlandFocusGrab {
    id: beeperFocusGrab
    windows: [window]
    // A click outside clears the grab without closing the messenger. Never
    // bind active to visibility: that would steal the keyboard back.
  }

  function focusBeeper() {
    if (!beeperActive || beeperNativeDialogOpen)
      return;
    beeperFocusGrab.active = true;
    beeperPanel.focusNavigation();
  }

  onBeeperActiveChanged: {
    if (beeperActive)
      Qt.callLater(focusBeeper);
    else {
      beeperFocusGrab.active = false;
      beeperNativeDialogOpen = false;
    }
  }

  Connections {
    target: window.statusData
    function onBeeperFocusSerialChanged() { Qt.callLater(window.focusBeeper); }
  }

  mask: Region {
    Region { item: leftModules }
    Region { item: centerMorph }
    Region { item: rightModules }
  }

  Component.onCompleted: entered = true

  Timer {
    id: fullscreenHideDelay
    interval: 360
  }

  Row {
    id: leftModules
    anchors.left: parent.left
    y: window.barTopInset
    spacing: 10
    opacity: window.entered ? 1 : 0
    transform: Translate {
      y: window.entered ? 0 : -10
      Behavior on y {
        NumberAnimation {
          duration: 420
          easing.type: Easing.OutCubic
        }
      }
    }
    Behavior on opacity { NumberAnimation { duration: 240 } }

    Pill {
      readonly property var forecast: statusData.weather.days[Calendar.dateKey(statusData.calendarToday)]
      readonly property string weatherIcon: Calendar.weatherIcon(forecast?.code)
      textFormat: Text.StyledText
      text: [
        " " + statusData.timeText,
        " " + statusData.dateText,
        (weatherIcon !== "" ? weatherIcon + "&nbsp;" : "") + statusData.weatherText
      ].join("&nbsp;&nbsp;&nbsp;")
      accent: Theme.sideWeather
      forceHovered: window.calendarActive
      interactive: true
      onLeftClicked: statusData.toggleCalendar(window.monitorName)
    }

    Pill {
      objectName: "systemPill"
      text: [
        " " + statusData.cpuUsage + "%",
        "  " + statusData.memoryUsage + "%",
        " " + statusData.gpuText
      ].join("   ")
      accent: Theme.sideSystem
      forceHovered: window.systemPanelActive
      interactive: true
      onLeftClicked: statusData.toggleSystemPanel(window.monitorName)
    }

    Pill {
      objectName: "storagePill"
      text: " " + statusData.diskUsage + "%"
      accent: Theme.sideDisk
    }
  }

  Rectangle {
    id: centerMorph
    GlassShape { anchors.fill: parent; radius: centerMorph.radius; enabled: GlassState.enabled }
    readonly property bool overlayVisible: window.notificationActive || window.volumeOverlayActive
      || window.audioSelectorActive || window.calendarActive || window.systemPanelActive
      || window.brightnessOverlayActive || window.mediaOverlayActive
      || window.appLauncherActive || window.chromeTabsActive
      || window.wifiSelectorActive || window.bluetoothSelectorActive
      || window.updateSelectorActive || window.dictationOverlayActive || window.beeperActive
    onOverlayVisibleChanged: {
      if (overlayVisible)
        fullscreenHideDelay.stop();
      else if (window.fullscreenActive)
        fullscreenHideDelay.restart();
    }
    readonly property string targetMode: window.beeperActive ? "beeper"
      : window.notificationActive ? "notification"
      : window.dictationOverlayActive
      ? "dictation" : window.systemPanelActive ? "system"
      : window.calendarActive ? "calendar"
      : window.audioSelectorActive ? "audio"
      : window.appLauncherActive ? "launcher"
      : window.chromeTabsActive ? "tabs"
      : window.updateSelectorActive ? "updates"
      : window.wifiSelectorActive ? "wifi"
      : window.bluetoothSelectorActive ? "bluetooth"
      : window.mediaOverlayActive ? "media"
      : window.volumeOverlayActive ? "volume"
      : window.brightnessOverlayActive ? "brightness" : "workspaces"
    readonly property real preferredWidth: window.beeperActive
      ? Math.max(320, Math.min(1280, window.width - 54)) : window.notificationActive
      ? notificationPopup.implicitWidth : window.dictationOverlayActive
      ? voiceDictationIndicator.implicitWidth
      : window.systemPanelActive ? workspaceSwitcher.expandedImplicitWidth
      : window.calendarActive ? workspaceSwitcher.expandedImplicitWidth
      : window.audioSelectorActive ? audioSelector.implicitWidth
      : window.appLauncherActive ? appLauncher.implicitWidth
      : window.chromeTabsActive ? chromeTabsLauncher.implicitWidth
      : window.updateSelectorActive ? updateSelector.implicitWidth
      : window.wifiSelectorActive ? wifiSelector.implicitWidth
      : window.bluetoothSelectorActive ? bluetoothSelector.implicitWidth
      : window.mediaOverlayActive ? nowPlayingIndicator.implicitWidth
      : overlayVisible ? 280 : workspaceSwitcher.implicitWidth
    readonly property real targetWidth: window.beeperActive ? preferredWidth
      : Math.min(preferredWidth, workspaceSwitcher.expandedImplicitWidth)
    readonly property real targetHeight: window.beeperActive
      ? window.beeperPanelHeight : window.notificationActive
      ? notificationPopup.implicitHeight : window.dictationOverlayActive
      ? voiceDictationIndicator.implicitHeight
      : window.systemPanelActive ? systemPanel.implicitHeight
      : window.calendarActive ? calendarPanel.implicitHeight
      : window.audioSelectorActive ? audioSelector.implicitHeight
      : window.appLauncherActive ? appLauncher.implicitHeight
      : window.chromeTabsActive ? chromeTabsLauncher.implicitHeight
      : window.updateSelectorActive ? updateSelector.implicitHeight
      : window.wifiSelectorActive ? wifiSelector.implicitHeight : 36
    readonly property var contentModes: ["workspaces", "volume", "audio",
      "brightness", "dictation", "media", "wifi", "bluetooth",
      "launcher", "tabs", "updates", "notification", "calendar", "system", "beeper"]
    property string visualSourceMode: "workspaces"
    property string visualTargetMode: "workspaces"
    property real transitionProgress: 1
    property real transitionDirection: 0
    property var startOpacities: ({ "workspaces": 1 })
    property var startOffsets: ({})

    function modeHeight(mode) {
      if (mode === "beeper") return window.beeperPanelHeight;
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
    y: window.beeperActive
      ? window.beeperWorkAreaTop + (window.beeperWorkAreaHeight - targetHeight) / 2
      : window.barTopInset
    width: targetWidth
    height: targetHeight
    radius: 18
    color: GlassState.enabled ? Qt.alpha(Theme.background, 0.12) : Theme.background
    clip: true
    opacity: window.entered ? 1 : 0

    Behavior on width {
      NumberAnimation {
        duration: 360
        easing.type: Easing.OutCubic
      }
    }

    Behavior on height {
      NumberAnimation {
        duration: 360
        easing.type: Easing.OutCubic
      }
    }

    Behavior on y {
      NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
    }

    NumberAnimation {
      id: contentTransition
      target: centerMorph
      property: "transitionProgress"
      from: 0
      to: 1
      duration: 360
      easing.type: Easing.Linear
    }

    transform: Translate {
      y: window.entered ? 0 : -12
      Behavior on y {
        NumberAnimation {
          duration: 420
          easing.type: Easing.OutCubic
        }
      }
    }

    Behavior on opacity { NumberAnimation { duration: 220 } }

    WorkspaceSwitcher {
      id: workspaceSwitcher
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("workspaces") }
      backgroundColor: "transparent"
      monitor: window.hyprlandMonitor
      opacity: centerMorph.contentOpacity("workspaces")
      enabled: !centerMorph.overlayVisible
    }

    VolumeIndicator {
      id: volumeIndicator
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("volume") }
      statusData: window.statusData
      targetMonitor: window.monitorName
      color: "transparent"
      opacity: centerMorph.contentOpacity("volume")
      enabled: window.volumeOverlayActive
    }

    AudioSelector {
      id: audioSelector
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("audio") }
      statusData: window.statusData
      opacity: centerMorph.contentOpacity("audio")
      enabled: window.audioSelectorKeyboardActive
    }

    BrightnessIndicator {
      id: brightnessIndicator
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("brightness") }
      statusData: window.statusData
      targetMonitor: window.monitorName
      color: "transparent"
      opacity: centerMorph.contentOpacity("brightness")
      enabled: window.brightnessOverlayActive
    }

    VoiceDictationIndicator {
      id: voiceDictationIndicator
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("dictation") }
      statusData: window.statusData
      color: "transparent"
      opacity: centerMorph.contentOpacity("dictation")
      enabled: window.dictationOverlayActive
    }

    NowPlayingIndicator {
      id: nowPlayingIndicator
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("media") }
      statusData: window.statusData
      opacity: centerMorph.contentOpacity("media")
      enabled: window.mediaOverlayActive
    }

    WifiSelector {
      id: wifiSelector
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("wifi") }
      statusData: window.statusData
      opacity: centerMorph.contentOpacity("wifi")
      enabled: window.wifiSelectorKeyboardActive
    }

    BluetoothSelector {
      id: bluetoothSelector
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("bluetooth") }
      statusData: window.statusData
      opacity: centerMorph.contentOpacity("bluetooth")
      enabled: window.bluetoothSelectorKeyboardActive
    }

    AppLauncher {
      id: appLauncher
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("launcher") }
      statusData: window.statusData
      opacity: centerMorph.contentOpacity("launcher")
      enabled: window.appLauncherKeyboardActive
    }

    ChromeTabsLauncher {
      id: chromeTabsLauncher
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("tabs") }
      statusData: window.statusData
      opacity: centerMorph.contentOpacity("tabs")
      enabled: window.chromeTabsKeyboardActive
    }

    UpdateSelector {
      id: updateSelector
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
      }
      height: implicitHeight
      transform: Translate { y: centerMorph.contentOffset("updates") }
      statusData: window.statusData
      opacity: centerMorph.contentOpacity("updates")
      enabled: window.updateSelectorKeyboardActive
    }

    SystemPanel {
      id: systemPanel
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      implicitWidth: workspaceSwitcher.expandedImplicitWidth
      height: implicitHeight
      statusData: window.statusData
      transform: Translate { y: centerMorph.contentOffset("system") }
      opacity: centerMorph.contentOpacity("system")
      visible: opacity > 0
      enabled: window.systemPanelKeyboardActive
    }

    CalendarPanel {
      id: calendarPanel
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      implicitWidth: workspaceSwitcher.expandedImplicitWidth
      height: implicitHeight
      statusData: window.statusData
      transform: Translate { y: centerMorph.contentOffset("calendar") }
      opacity: centerMorph.contentOpacity("calendar")
      enabled: window.calendarKeyboardActive
    }

    BeeperPanel {
      id: beeperPanel
      anchors.fill: parent
      beeperData: window.statusData.beeper
      active: window.beeperActive
      windowFocused: window.contentItem.Window.active && !window.beeperNativeDialogOpen
      opacity: centerMorph.contentOpacity("beeper")
      visible: opacity > 0
      enabled: window.beeperActive
      onCloseRequested: window.statusData.hideBeeper()
      onNativeDialogOpened: {
        window.beeperNativeDialogOpen = true;
        beeperFocusGrab.active = false;
      }
      onNativeDialogClosed: {
        window.beeperNativeDialogOpen = false;
        Qt.callLater(() => {
          if (window.beeperActive) {
            beeperFocusGrab.active = true;
            beeperPanel.forceActiveFocus();
          }
        });
      }
    }

    Rectangle {
      id: beeperNotificationBanner
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 16
      width: Math.min(420, parent.width - 32)
      height: beeperNotification.implicitHeight
      radius: 16
      color: Theme.surfaceRaised
      border.color: Theme.surfaceSelected
      visible: window.beeperNotificationActive
      z: 4
      NotificationPopup {
        id: beeperNotification
        anchors.fill: parent
        maximumWidth: 420
        fontScale: 1.35
        notificationData: window.statusData.notifications
      }
    }

    Rectangle {
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.topMargin: 16
      width: 250
      height: 32
      radius: 16
      color: Theme.surfaceRaised
      visible: window.beeperDictationActive
      z: 3
      Text {
        anchors.centerIn: parent
        text: window.statusData.voiceDictationTranscribing ? "Dictée · transcription…" : "●  Dictée en cours"
        color: Theme.state
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: Theme.beeperFont.secondary
      }
    }

    NotificationInputGuard {
      id: notificationKeyboardShield
      anchors.fill: parent
      active: window.notificationActive
      captureInput: window.keyboardSelectorActive
      z: 1
      onDismissed: window.statusData.notifications.close()
    }

    NotificationPopup {
      id: notificationPopup
      maximumWidth: workspaceSwitcher.expandedImplicitWidth
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: implicitHeight
      notificationData: window.statusData.notifications
      transform: Translate { y: centerMorph.contentOffset("notification") }
      opacity: centerMorph.contentOpacity("notification")
      enabled: window.notificationActive
      z: 2
    }
  }

  Row {
    id: rightModules
    anchors.right: parent.right
    y: window.barTopInset
    spacing: 10
    opacity: window.entered ? 1 : 0
    transform: Translate {
      y: window.entered ? 0 : -10
      Behavior on y {
        NumberAnimation {
          duration: 420
          easing.type: Easing.OutCubic
        }
      }
    }
    Behavior on opacity { NumberAnimation { duration: 240 } }

    Pill {
      visible: statusData.batteryAvailable || statusData.keyboardBatteries.length > 0
      textFormat: Text.StyledText
      text: (statusData.batteryAvailable
        ? [batteryLabel("󰌢", statusData.batteryPercent, statusData.batteryPluggedIn)] : [])
        .concat(statusData.keyboardBatteries.map(device =>
          batteryLabel("󰌌", device.percent, device.pluggedIn)))
        .join("&nbsp;&nbsp;&nbsp;")
      accent: Theme.sideBattery

      function batteryLabel(icon, percent, pluggedIn) {
        const iconColor = pluggedIn ? Theme.batteryPluggedIn
          : percent !== null && percent < 20 ? Theme.error : "";
        return (iconColor !== "" ? '<font color="' + iconColor + '">' + icon + '</font>' : icon)
          + "&nbsp;" + (percent === null ? "--" : percent) + "%";
      }
    }

    Pill {
      text: statusData.audioIcon() + " " + statusData.audioVolume + "%"
      trailingText: !statusData.microphoneAvailable || statusData.microphoneMuted
        ? "󰍭" : "󰍬"
      trailingInactive: !statusData.microphoneAvailable
      accent: Theme.sideVolume
      forceHovered: window.volumeOverlayActive || window.audioSelectorActive
        || (statusData.microphoneFeedbackActive
          && window.monitorName === statusData.microphoneFeedbackTargetMonitor)
      interactive: true
      onLeftClicked: statusData.toggleAudioSelector(window.monitorName)
      onWheelUp: {
        statusData.setVolume(statusData.volumeStep);
        statusData.showVolumeOverlay(window.monitorName);
      }
      onWheelDown: {
        statusData.setVolume(-statusData.volumeStep);
        statusData.showVolumeOverlay(window.monitorName);
      }
    }

    Pill {
      text: statusData.brightnessIcon() + " " + statusData.brightness + "%"
      accent: Theme.sideBrightness
      forceHovered: window.brightnessOverlayActive
      interactive: true
      onWheelUp: statusData.changeBrightness(5, window.monitorName)
      onWheelDown: statusData.changeBrightness(-5, window.monitorName)
    }

    Pill {
      iconOnly: true
      text: statusData.displayedNixIcon
      accent: Theme.sideUpdates
      forceHovered: window.updateSelectorActive
      interactive: true
      onLeftClicked: statusData.toggleUpdateSelector(window.monitorName)
      onRightClicked: statusData.forceNixStatus()
    }

    Pill {
      iconOnly: true
      text: statusData.networkIcon()
      accent: Theme.sideNetwork
      forceHovered: window.wifiSelectorActive
      interactive: true
      onLeftClicked: statusData.toggleWifiSelector(window.monitorName)
    }

    Pill {
      iconOnly: true
      text: statusData.bluetoothConnected ? "󰂯" : "󰂲"
      accent: Theme.sideBluetooth
      forceHovered: window.bluetoothSelectorActive
      interactive: true
      onLeftClicked: statusData.toggleBluetoothSelector(window.monitorName)
    }

    Pill {
      objectName: "doNotDisturbPill"
      iconOnly: true
      text: statusData.notifications.doNotDisturb ? "󰂛" : "󰂚"
      accent: Theme.sideNotifications
      forceHovered: statusData.notifications.dndFeedbackActive
        && statusData.notifications.dndFeedbackTargetMonitor === window.monitorName
      interactive: true
      onLeftClicked: statusData.notifications.toggleDoNotDisturb(window.monitorName)
      onRightClicked: Quickshell.execDetached([
        "hyprctl", "eval",
        "local disabled = not quickshell_internal_keyboard_disabled; "
          + "hl.device({name = 'at-translated-set-2-keyboard', enabled = not disabled}); "
          + "quickshell_internal_keyboard_disabled = disabled"
      ])
    }
  }

}
