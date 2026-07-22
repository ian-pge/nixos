import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "components"

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
  readonly property bool wifiSelectorActive: statusData.wifiSelectorVisible
  readonly property bool bluetoothSelectorActive: statusData.bluetoothSelectorVisible
  readonly property bool updateSelectorActive: statusData.updateSelectorVisible
  readonly property bool wifiSelectorKeyboardActive: wifiSelectorActive
    && hyprlandMonitor !== null
    && hyprlandMonitor.name === statusData.wifiTargetMonitor
  readonly property bool bluetoothSelectorKeyboardActive: bluetoothSelectorActive
    && hyprlandMonitor !== null
    && hyprlandMonitor.name === statusData.bluetoothTargetMonitor
  readonly property bool updateSelectorKeyboardActive: updateSelectorActive
    && hyprlandMonitor !== null
    && hyprlandMonitor.name === statusData.updateTargetMonitor
  readonly property bool keyboardSelectorActive: wifiSelectorKeyboardActive
    || bluetoothSelectorKeyboardActive || updateSelectorKeyboardActive

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
      accent: "#7dc4e4"
      leftCommand: "pgrep -x fuzzel >/dev/null 2>&1 || fuzzel"
    }

    Pill {
      text: statusData.nixIcon
      accent: "#f0c6c6"
      tooltipText: statusData.nixTooltip
      tooltipHost: window
      interactive: true
      onLeftClicked: statusData.toggleUpdateSelector()
      onRightClicked: statusData.forceNixStatus()
    }

    Pill {
      text: statusData.networkIcon()
      accent: "#ee99a0"
      tooltipText: statusData.networkName
      tooltipHost: window
      interactive: true
      onLeftClicked: statusData.toggleWifiSelector()
    }

    Pill {
      text: statusData.bluetoothConnected ? "󰂯" : "󰂲"
      accent: "#8aadf4"
      tooltipText: statusData.bluetoothTooltip
      tooltipHost: window
      interactive: true
      onLeftClicked: statusData.toggleBluetoothSelector()
    }

    Pill {
      text: " " + statusData.diskUsage + "%"
      accent: "#f5a97f"
      leftCommand: "ghostty -e ncdu"
    }

    Pill {
      text: " " + statusData.cpuUsage + "%"
      accent: "#91d7e3"
      leftCommand: "ghostty -e htop"
    }

    Pill {
      text: "  " + statusData.memoryUsage + "%"
      accent: "#c6a0f6"
      leftCommand: "ghostty -e htop"
    }

    Pill {
      text: " " + statusData.gpuText
      accent: "#a6da95"
      tooltipText: statusData.gpuTooltip
      tooltipHost: window
      leftCommand: "ghostty -e nvtop"
    }
  }

  Rectangle {
    id: centerMorph
    readonly property bool overlayVisible: statusData.volumeOverlayVisible
      || statusData.brightnessOverlayVisible || window.wifiSelectorActive
      || window.bluetoothSelectorActive || window.updateSelectorActive

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    width: window.updateSelectorActive ? updateSelector.implicitWidth
      : window.wifiSelectorActive ? wifiSelector.implicitWidth
      : window.bluetoothSelectorActive ? bluetoothSelector.implicitWidth
      : overlayVisible ? 280 : workspaceSwitcher.implicitWidth
    height: window.updateSelectorActive ? updateSelector.implicitHeight : 36
    radius: 18
    color: "#181926"
    clip: true
    opacity: window.entered ? 1 : 0
    transform: Translate {
      y: window.entered ? 0 : -12
      Behavior on y {
        NumberAnimation {
          duration: 450
          easing.type: Easing.OutBack
        }
      }
    }

    Behavior on width {
      NumberAnimation {
        duration: 300
        easing.type: Easing.OutBack
        easing.overshoot: statusData.updateMorphGentle ? 1.8 : 5.5
      }
    }

    Behavior on height {
      NumberAnimation {
        duration: 300
        easing.type: Easing.OutBack
        easing.overshoot: 1.8
      }
    }

    Behavior on opacity { NumberAnimation { duration: 220 } }

    WorkspaceSwitcher {
      id: workspaceSwitcher
      anchors.fill: parent
      backgroundColor: "transparent"
      monitorName: window.hyprlandMonitor !== null
        ? window.hyprlandMonitor.name : ""
      opacity: centerMorph.overlayVisible ? 0 : 1
      enabled: !centerMorph.overlayVisible

    }

    VolumeIndicator {
      anchors.fill: parent
      statusData: window.statusData
      color: "transparent"
      opacity: statusData.volumeOverlayVisible ? 1 : 0
      enabled: statusData.volumeOverlayVisible

    }

    BrightnessIndicator {
      anchors.fill: parent
      statusData: window.statusData
      color: "transparent"
      opacity: statusData.brightnessOverlayVisible ? 1 : 0
      enabled: statusData.brightnessOverlayVisible

    }

    WifiSelector {
      id: wifiSelector
      anchors.fill: parent
      statusData: window.statusData
      opacity: window.wifiSelectorActive ? 1 : 0
      enabled: window.wifiSelectorKeyboardActive

    }

    BluetoothSelector {
      id: bluetoothSelector
      anchors.fill: parent
      statusData: window.statusData
      opacity: window.bluetoothSelectorActive ? 1 : 0
      enabled: window.bluetoothSelectorKeyboardActive

    }

    UpdateSelector {
      id: updateSelector
      anchors.fill: parent
      statusData: window.statusData
      presented: window.updateSelectorActive
      opacity: window.updateSelectorActive ? 1 : 0
      enabled: window.updateSelectorKeyboardActive
    }

    Item {
      id: activityBorder
      anchors.fill: parent
      visible: centerMorph.overlayVisible
      z: 100

      property real phase: 0
      readonly property real inset: 2
      readonly property real pathRadius: Math.min(16,
        Math.max(0, width / 2 - inset), Math.max(0, height / 2 - inset))
      readonly property real horizontalLength: Math.max(0,
        width - inset * 2 - pathRadius * 2)
      readonly property real verticalLength: Math.max(0,
        height - inset * 2 - pathRadius * 2)
      readonly property real arcLength: Math.PI * pathRadius / 2
      readonly property real perimeter: Math.max(1,
        horizontalLength * 2 + verticalLength * 2 + arcLength * 4)

      function pointAt(normalizedPosition) {
        let distance = (normalizedPosition - Math.floor(normalizedPosition))
          * perimeter;
        const radius = Math.max(0.001, pathRadius);
        let angle = 0;

        if (distance <= horizontalLength)
          return { "x": inset + pathRadius + distance, "y": inset };
        distance -= horizontalLength;

        if (distance <= arcLength) {
          angle = -Math.PI / 2 + distance / radius;
          return { "x": width - inset - pathRadius + Math.cos(angle) * radius,
            "y": inset + pathRadius + Math.sin(angle) * radius };
        }
        distance -= arcLength;

        if (distance <= verticalLength)
          return { "x": width - inset,
            "y": inset + pathRadius + distance };
        distance -= verticalLength;

        if (distance <= arcLength) {
          angle = distance / radius;
          return { "x": width - inset - pathRadius + Math.cos(angle) * radius,
            "y": height - inset - pathRadius + Math.sin(angle) * radius };
        }
        distance -= arcLength;

        if (distance <= horizontalLength)
          return { "x": width - inset - pathRadius - distance,
            "y": height - inset };
        distance -= horizontalLength;

        if (distance <= arcLength) {
          angle = Math.PI / 2 + distance / radius;
          return { "x": inset + pathRadius + Math.cos(angle) * radius,
            "y": height - inset - pathRadius + Math.sin(angle) * radius };
        }
        distance -= arcLength;

        if (distance <= verticalLength)
          return { "x": inset,
            "y": height - inset - pathRadius - distance };
        distance -= verticalLength;

        angle = Math.PI + distance / radius;
        return { "x": inset + pathRadius + Math.cos(angle) * radius,
          "y": inset + pathRadius + Math.sin(angle) * radius };
      }

      Repeater {
        model: 220

        Rectangle {
          readonly property real trailPosition: index / 219
          readonly property var pathPoint: activityBorder.pointAt(
            activityBorder.phase - trailPosition * 0.50)

          x: pathPoint.x - width / 2
          y: pathPoint.y - height / 2
          width: 3.5
          height: 3.5
          radius: 1.75
          color: "#ff33cc"
          opacity: Math.pow(1 - trailPosition, 1.35)
        }
      }

      FrameAnimation {
        running: activityBorder.visible
        onTriggered: {
          const delta = Math.min(frameTime, 0.05);
          activityBorder.phase += delta / 1.6;
        }
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
      accent: "#f4dbd6"
    }

    Pill {
      text: statusData.audioMuted
        ? "󰖁"
        : statusData.audioIcon() + " " + statusData.audioVolume + "%"
      accent: "#b7bdf8"
      leftCommand: "pgrep -x pulsemixer >/dev/null 2>&1 || ghostty --class=dev.me.audio --title=Audio -e pulsemixer"
      interactive: true
      onWheelUp: {
        statusData.setVolume(0.02);
        statusData.showVolumeOverlay();
      }
      onWheelDown: {
        statusData.setVolume(-0.02);
        statusData.showVolumeOverlay();
      }
    }

    Pill {
      text: statusData.brightnessIcon() + " " + statusData.brightness + "%"
      accent: "#eed49f"
      wheelUpCommand: "brightnessctl set +5%"
      wheelDownCommand: "brightnessctl set 5%-"
      onWheelUp: statusData.showBrightnessOverlay()
      onWheelDown: statusData.showBrightnessOverlay()
    }

    Pill {
      text: statusData.weatherText
      accent: "#f5bde6"
      tooltipText: statusData.weatherTooltip
      tooltipHost: window
    }

    Pill {
      text: " " + statusData.dateText
      accent: "#8bd5ca"
    }

    Pill {
      text: " " + statusData.timeText
      accent: "#ed8796"
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
      color: "#363a4f"

      Text {
        id: tooltipLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 10
        text: window.tooltipText
        color: "#cad3f5"
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 14
        font.bold: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
      }
    }
  }
}
