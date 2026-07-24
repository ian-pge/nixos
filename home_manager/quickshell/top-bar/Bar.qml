import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "components"
import "components/Theme.js" as Theme

PanelWindow {
  id: window

  required property var modelData
  required property var statusData

  property bool entered: false
  property var pendingTooltipAnchor: null
  property var tooltipAnchor: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipVisible: false
  readonly property var hyprlandMonitor: Hyprland.monitorFor(window.screen)
  readonly property string monitorName: hyprlandMonitor !== null
    ? hyprlandMonitor.name : ""
  readonly property bool volumeOverlayActive: statusData.volumeOverlayVisible
    && monitorName === statusData.volumeTargetMonitor
  readonly property bool brightnessOverlayActive: statusData.brightnessOverlayVisible
    && monitorName === statusData.brightnessTargetMonitor
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
    || appLauncherKeyboardActive || chromeTabsKeyboardActive

  screen: modelData

  anchors {
    top: true
    left: true
    right: true
  }

  margins {
    top: 10
    left: 5
    right: 5
  }

  // Keep the layer surface geometry fixed so expanding the update card cannot
  // nudge the other bar modules. The mask leaves the unused area click-through.
  implicitHeight: 600
  color: "transparent"
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 36
  aboveWindows: true
  WlrLayershell.namespace: "quickshell-top-bar"
  WlrLayershell.keyboardFocus: keyboardSelectorActive
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  mask: Region {
    Region { item: leftModules }
    Region { item: centerMorph }
    Region { item: rightModules }
  }

  Component.onCompleted: entered = true

  function showTooltip(item, text) {
    pendingTooltipAnchor = item;
    pendingTooltipText = text;
    tooltipDelay.restart();
  }

  function hideTooltip(item) {
    if (pendingTooltipAnchor === item) {
      tooltipDelay.stop();
      pendingTooltipAnchor = null;
    }
    if (tooltipAnchor === item) {
      tooltipVisible = false;
      tooltipAnchor = null;
    }
  }

  Timer {
    id: tooltipDelay
    interval: 300
    onTriggered: {
      window.tooltipAnchor = window.pendingTooltipAnchor;
      window.tooltipText = window.pendingTooltipText;
      window.tooltipVisible = window.tooltipAnchor !== null;
    }
  }

  Row {
    id: leftModules
    anchors.left: parent.left
    y: 0
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
      text: ""
      accent: Theme.sideApplications
      forceHovered: window.appLauncherActive
      tooltipText: "Applications"
      tooltipHost: window
      interactive: true
      onLeftClicked: statusData.toggleAppLauncher(window.monitorName)
    }

    Pill {
      text: statusData.nixIcon
      accent: Theme.sideUpdates
      forceHovered: window.updateSelectorActive
      tooltipText: statusData.nixTooltip
      tooltipHost: window
      interactive: true
      onLeftClicked: statusData.toggleUpdateSelector(window.monitorName)
      onRightClicked: statusData.forceNixStatus()
    }

    Pill {
      text: statusData.networkIcon()
      accent: Theme.sideNetwork
      forceHovered: window.wifiSelectorActive
      tooltipText: statusData.networkName
      tooltipHost: window
      interactive: true
      onLeftClicked: statusData.toggleWifiSelector(window.monitorName)
    }

    Pill {
      text: statusData.bluetoothConnected ? "󰂯" : "󰂲"
      accent: Theme.sideBluetooth
      forceHovered: window.bluetoothSelectorActive
      tooltipText: statusData.bluetoothTooltip
      tooltipHost: window
      interactive: true
      onLeftClicked: statusData.toggleBluetoothSelector(window.monitorName)
    }

    Pill {
      text: " " + statusData.diskUsage + "%"
      accent: Theme.sideDisk
      leftCommand: "ghostty -e ncdu"
    }

    Pill {
      text: " " + statusData.cpuUsage + "%"
      accent: Theme.sideCpu
      leftCommand: "ghostty -e htop"
    }

    Pill {
      text: "  " + statusData.memoryUsage + "%"
      accent: Theme.sideMemory
      leftCommand: "ghostty -e htop"
    }

    Pill {
      text: " " + statusData.gpuText
      accent: Theme.sideGpu
      tooltipText: statusData.gpuTooltip
      tooltipHost: window
      leftCommand: "ghostty -e nvtop"
    }
  }

  Rectangle {
    id: centerMorph
    readonly property bool overlayVisible: window.volumeOverlayActive
      || window.brightnessOverlayActive || window.mediaOverlayActive
      || window.appLauncherActive || window.chromeTabsActive
      || window.wifiSelectorActive || window.bluetoothSelectorActive
      || window.updateSelectorActive
    readonly property string targetMode: window.appLauncherActive
      ? "launcher" : window.chromeTabsActive ? "tabs"
      : window.updateSelectorActive ? "updates"
      : window.wifiSelectorActive ? "wifi"
      : window.bluetoothSelectorActive ? "bluetooth"
      : window.mediaOverlayActive ? "media"
      : window.volumeOverlayActive ? "volume"
      : window.brightnessOverlayActive ? "brightness" : "workspaces"
    readonly property real targetWidth: window.appLauncherActive
      ? appLauncher.implicitWidth
      : window.chromeTabsActive ? chromeTabsLauncher.implicitWidth
      : window.updateSelectorActive ? updateSelector.implicitWidth
      : window.wifiSelectorActive ? wifiSelector.implicitWidth
      : window.bluetoothSelectorActive ? bluetoothSelector.implicitWidth
      : window.mediaOverlayActive ? nowPlayingIndicator.implicitWidth
      : overlayVisible ? 280 : workspaceSwitcher.implicitWidth
    readonly property real targetHeight: window.appLauncherActive
      ? appLauncher.implicitHeight
      : window.chromeTabsActive ? chromeTabsLauncher.implicitHeight
      : window.updateSelectorActive ? updateSelector.implicitHeight : 36
    readonly property var contentModes: ["workspaces", "volume",
      "brightness", "media", "wifi", "bluetooth", "launcher", "tabs",
      "updates"]
    property string visualSourceMode: "workspaces"
    property string visualTargetMode: "workspaces"
    property real transitionProgress: 1
    property real transitionDirection: 0
    property var startOpacities: ({ "workspaces": 1 })
    property var startOffsets: ({})

    function modeHeight(mode) {
      if (mode === "launcher") return appLauncher.implicitHeight;
      if (mode === "tabs") return chromeTabsLauncher.implicitHeight;
      if (mode === "updates") return updateSelector.implicitHeight;
      if (mode === "wifi") return wifiSelector.implicitHeight;
      if (mode === "bluetooth") return bluetoothSelector.implicitHeight;
      if (mode === "media") return nowPlayingIndicator.implicitHeight;
      if (mode === "volume") return volumeIndicator.implicitHeight;
      if (mode === "brightness") return brightnessIndicator.implicitHeight;
      return workspaceSwitcher.implicitHeight;
    }

    function localTransitionMode(mode, targetMonitor) {
      return mode === "workspaces" || targetMonitor === window.monitorName
        ? mode : "workspaces";
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
    anchors.top: parent.top
    width: targetWidth
    height: targetHeight
    radius: 18
    color: Theme.background
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

    NumberAnimation {
      id: contentTransition
      target: centerMorph
      property: "transitionProgress"
      from: 0
      to: 1
      duration: 360
      easing.type: Easing.Linear
    }

    Connections {
      target: window.statusData

      function onCenterTransitionSerialChanged() {
        const sourceMode = centerMorph.localTransitionMode(
          window.statusData.centerTransitionSourceMode,
          window.statusData.centerTransitionSourceMonitor);
        const targetMode = centerMorph.localTransitionMode(
          window.statusData.centerTransitionTargetMode,
          window.statusData.centerTransitionTargetMonitor);
        centerMorph.startContentTransition(sourceMode, targetMode);
      }
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
      monitorName: window.monitorName
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

    ShaderEffect {
      id: activityBorder
      anchors.fill: parent
      visible: centerMorph.overlayVisible
      z: 100

      property size itemSize: Qt.size(width, height)
      property real phase: 0
      fragmentShader: Qt.resolvedUrl(
        "shaders/activity-border.frag.qsb")

      NumberAnimation on phase {
        from: 0
        to: 1
        duration: 1600
        loops: Animation.Infinite
        running: activityBorder.visible
      }
    }
  }

  Row {
    id: rightModules
    anchors.right: parent.right
    y: 0
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
      visible: statusData.batteryAvailable
      text: statusData.batteryIcon() + " " + statusData.batteryPercent + "%"
      accent: Theme.sideBattery
    }

    Pill {
      text: statusData.audioMuted
        ? "󰖁"
        : statusData.audioIcon() + " " + statusData.audioVolume + "%"
      accent: Theme.sideVolume
      forceHovered: window.volumeOverlayActive
      leftCommand: "pgrep -x pulsemixer >/dev/null 2>&1 || ghostty --class=dev.me.audio --title=Audio -e pulsemixer"
      interactive: true
      onWheelUp: {
        statusData.setVolume(0.02);
        statusData.showVolumeOverlay(window.monitorName);
      }
      onWheelDown: {
        statusData.setVolume(-0.02);
        statusData.showVolumeOverlay(window.monitorName);
      }
    }

    Pill {
      text: statusData.brightnessIcon() + " " + statusData.brightness + "%"
      accent: Theme.sideBrightness
      forceHovered: window.brightnessOverlayActive
      wheelUpCommand: "brightnessctl set +5%"
      wheelDownCommand: "brightnessctl set 5%-"
      onWheelUp: statusData.showBrightnessOverlay(window.monitorName)
      onWheelDown: statusData.showBrightnessOverlay(window.monitorName)
    }

    Pill {
      text: statusData.weatherText
      accent: Theme.sideWeather
      tooltipText: statusData.weatherTooltip
      tooltipHost: window
    }

    Pill {
      text: " " + statusData.dateText
      accent: Theme.sideDate
    }

    Pill {
      text: " " + statusData.timeText
      accent: Theme.sideTime
    }
  }

  PopupWindow {
    id: tooltip

    anchor.window: window
    anchor.rect.x: {
      if (window.tooltipAnchor === null)
        return 0;
      const point = window.tooltipAnchor.mapToItem(window.contentItem, 0, 0);
      return Math.max(0, Math.min(window.width - width,
        point.x + window.tooltipAnchor.width / 2 - width / 2));
    }
    anchor.rect.y: 42

    implicitWidth: Math.min(620, Math.max(120, window.tooltipText.length * 7 + 24))
    implicitHeight: tooltipLabel.implicitHeight + 20
    visible: window.tooltipVisible
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      radius: 14
      color: Theme.surfaceRaised

      Text {
        id: tooltipLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        text: window.tooltipText
        color: Theme.foreground
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 14
        font.bold: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
      }
    }
  }
}
