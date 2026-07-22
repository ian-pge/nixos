import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

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
  readonly property bool wifiSelectorKeyboardActive: wifiSelectorActive
    && hyprlandMonitor !== null
    && hyprlandMonitor.name === statusData.wifiTargetMonitor
  readonly property bool bluetoothSelectorKeyboardActive: bluetoothSelectorActive
    && hyprlandMonitor !== null
    && hyprlandMonitor.name === statusData.bluetoothTargetMonitor
  readonly property bool keyboardSelectorActive: wifiSelectorKeyboardActive
    || bluetoothSelectorKeyboardActive

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

  implicitHeight: 36
  color: "transparent"
  exclusionMode: ExclusionMode.Auto
  aboveWindows: true
  WlrLayershell.namespace: "quickshell-top-bar"
  WlrLayershell.keyboardFocus: keyboardSelectorActive
    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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
    anchors.verticalCenter: parent.verticalCenter
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
      leftCommand: "ghostty -e nixos-update-installer"
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
      || window.bluetoothSelectorActive

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: window.wifiSelectorActive ? wifiSelector.implicitWidth
      : window.bluetoothSelectorActive ? bluetoothSelector.implicitWidth
      : overlayVisible ? 280 : workspaceSwitcher.implicitWidth
    height: 36
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
        easing.overshoot: 5.5
      }
    }

    Behavior on opacity { NumberAnimation { duration: 220 } }

    WorkspaceSwitcher {
      id: workspaceSwitcher
      anchors.fill: parent
      backgroundColor: "transparent"
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
  }

  Row {
    id: rightModules
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
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
    anchor.rect.y: window.height + 6

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
