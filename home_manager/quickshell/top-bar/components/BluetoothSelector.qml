import Quickshell.Bluetooth
import QtQuick
import "Layout.js" as Layout
import "Theme.js" as Theme

FocusScope {
  id: root

  required property var statusData
  readonly property var devices: statusData.bluetoothSelectorDevices.filter(device =>
    statusData.bluetoothTab === 0 ? device.paired : !device.paired)
  readonly property var selectedDevice: devices.length > 0
    ? devices[Math.min(statusData.bluetoothSelectedIndex, devices.length - 1)]
    : null
  readonly property bool selectedDeviceConnected: selectedDevice !== null
    && Bluetooth.devices.values.some(device => device.address === selectedDevice.address
      && device.connected)
  readonly property string desiredLabelText: {
    if (statusData.bluetoothSelectorMessage !== "")
      return statusData.bluetoothSelectorMessage;
    if (statusData.bluetoothSelectorLoading)
      return statusData.bluetoothTab === 0 ? "Loading paired devices…" : "Scanning nearby devices…";
    return selectedDevice !== null ? selectedDevice.name : "No devices found";
  }

  property string displayedLabelText: ""
  property string previousLabelText: ""
  property bool componentReady: false
  property bool wheelNavigationPending: false
  readonly property string bluetoothIconText:
    statusData.bluetoothSelectorScanning ? statusData.brailleFrame
      : selectedDeviceConnected ? "󰂯" : "󰂲"
  readonly property string tabText: statusData.bluetoothTab === 0
    ? "PAIRED" : "NEARBY"
  readonly property string counterText: devices.length > 0
    ? (statusData.bluetoothSelectedIndex + 1) + "/" + devices.length : "0/0"
  readonly property real contentWidth: 15
    + bluetoothIconMetrics.advanceWidth(bluetoothIconText) + 13 + 7 + 8
    + Layout.widestText(labelMetrics,
      [desiredLabelText, displayedLabelText, previousLabelText])
    + 12 + tabMetrics.advanceWidth(tabText) + 8
    + counterMetrics.advanceWidth(counterText) + 15

  implicitWidth: Layout.boundedWidth(contentWidth, 0, 400)
  implicitHeight: 36

  FontMetrics {
    id: bluetoothIconMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 17
    font.bold: true
  }

  FontMetrics {
    id: labelMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 14
    font.bold: true
  }

  FontMetrics {
    id: tabMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 11
    font.bold: true
  }

  FontMetrics {
    id: counterMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 12
    font.bold: true
  }

  function syncLabel() {
    selectionWheel.stop();
    previousLabelText = "";
    outgoingLabel.visible = false;
    incomingSlide.y = 0;
    displayedLabelText = desiredLabelText;
  }

  function animateLabel() {
    if (desiredLabelText === displayedLabelText)
      return;
    selectionWheel.stop();
    outgoingSlide.y = 0;
    incomingSlide.y = statusData.bluetoothSelectionDirection > 0 ? 40 : -40;
    previousLabelText = displayedLabelText;
    outgoingLabel.visible = true;
    displayedLabelText = desiredLabelText;
    selectionWheel.restart();
  }

  Component.onCompleted: {
    componentReady = true;
    syncLabel();
  }

  onDesiredLabelTextChanged: {
    if (!componentReady)
      return;
    if (!wheelNavigationPending || !enabled || statusData.bluetoothSelectorLoading
        || statusData.bluetoothSelectorMessage !== "")
      syncLabel();
    else
      animateLabel();
  }

  onEnabledChanged: {
    if (enabled)
      Qt.callLater(() => root.forceActiveFocus());
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Tab) {
      statusData.switchBluetoothTab();
      event.accepted = true;
    } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down
        || event.key === Qt.Key_L || event.key === Qt.Key_Right) {
      wheelNavigationPending = true;
      statusData.moveBluetoothSelection(1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up
        || event.key === Qt.Key_H || event.key === Qt.Key_Left) {
      wheelNavigationPending = true;
      statusData.moveBluetoothSelection(-1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_R) {
      statusData.refreshBluetoothSelectorDevices(statusData.bluetoothTab === 1);
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      statusData.activateSelectedBluetoothDevice();
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
      statusData.hideBluetoothSelector();
      event.accepted = true;
    }
  }

  Text {
    id: bluetoothIcon
    anchors.left: parent.left
    anchors.leftMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    text: root.bluetoothIconText
    color: Theme.sideBluetooth
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 17
    font.bold: true

  }

  Rectangle {
    id: activeDot
    anchors.left: bluetoothIcon.right
    anchors.leftMargin: 13
    anchors.verticalCenter: parent.verticalCenter
    width: 7
    height: 7
    radius: 3.5
    color: root.selectedDeviceConnected ? Theme.sideBluetooth : Theme.inactive
  }

  Item {
    id: labelViewport
    anchors.left: activeDot.right
    anchors.leftMargin: 8
    anchors.right: bluetoothStatus.left
    anchors.rightMargin: 12
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    clip: true

    Text {
      id: outgoingLabel
      visible: false
      text: root.previousLabelText
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      transform: Translate { id: outgoingSlide }
      color: Theme.foreground
      elide: Text.ElideNone
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      id: incomingLabel
      text: root.displayedLabelText
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      transform: Translate { id: incomingSlide }
      color: Theme.foreground
      elide: Text.ElideNone
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }
  }

  ParallelAnimation {
    id: selectionWheel
    onStopped: {
      outgoingLabel.visible = false;
      root.previousLabelText = "";
    }

    NumberAnimation {
      target: outgoingSlide
      property: "y"
      from: 0
      to: statusData.bluetoothSelectionDirection > 0 ? -40 : 40
      duration: 150
      easing.type: Easing.InOutCubic
    }

    NumberAnimation {
      target: incomingSlide
      property: "y"
      from: statusData.bluetoothSelectionDirection > 0 ? 40 : -40
      to: 0
      duration: 150
      easing.type: Easing.InOutCubic
    }
  }

  Row {
    id: bluetoothStatus
    anchors.right: parent.right
    anchors.rightMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8

    Text {
      text: root.tabText
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: Theme.sideBluetooth
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 11
      font.bold: true
    }

    Text {
      text: root.counterText
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 12
      font.bold: true
    }
  }
}
