import Quickshell.Bluetooth
import QtQuick

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
  property bool componentReady: false
  property bool wheelNavigationPending: false

  implicitWidth: 400
  implicitHeight: 36

  function syncLabel() {
    selectionWheel.stop();
    outgoingLabel.visible = false;
    incomingSlide.y = 0;
    incomingLabel.text = desiredLabelText;
    displayedLabelText = desiredLabelText;
  }

  function animateLabel() {
    if (desiredLabelText === displayedLabelText)
      return;
    selectionWheel.stop();
    outgoingSlide.y = 0;
    incomingSlide.y = statusData.bluetoothSelectionDirection > 0 ? 40 : -40;
    outgoingLabel.text = displayedLabelText;
    outgoingLabel.visible = true;
    incomingLabel.text = desiredLabelText;
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
    text: statusData.bluetoothSelectorScanning ? "󰑐"
      : root.selectedDeviceConnected ? "󰂯" : "󰂲"
    color: "#8aadf4"
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 17
    font.bold: true

    RotationAnimator on rotation {
      running: statusData.bluetoothSelectorScanning
      from: 0
      to: 360
      duration: 900
      loops: Animation.Infinite
      onStopped: bluetoothIcon.rotation = 0
    }
  }

  Rectangle {
    id: activeDot
    anchors.left: bluetoothIcon.right
    anchors.leftMargin: 13
    anchors.verticalCenter: parent.verticalCenter
    width: 7
    height: 7
    radius: 3.5
    color: root.selectedDeviceConnected ? "#a6da95"
      : root.selectedDevice !== null && root.selectedDevice.paired ? "#8aadf4" : "#6e738d"
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
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      transform: Translate { id: outgoingSlide }
      color: "#cad3f5"
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      id: incomingLabel
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      transform: Translate { id: incomingSlide }
      color: "#cad3f5"
      elide: Text.ElideRight
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }
  }

  ParallelAnimation {
    id: selectionWheel
    onStopped: outgoingLabel.visible = false

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
      text: statusData.bluetoothTab === 0 ? "PAIRED" : "NEARBY"
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: statusData.bluetoothTab === 0 ? "#8aadf4" : "#c6a0f6"
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 11
      font.bold: true
    }

    Text {
      text: root.devices.length > 0
        ? (statusData.bluetoothSelectedIndex + 1) + "/" + root.devices.length : "0/0"
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: "#939ab7"
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 12
      font.bold: true
    }
  }
}
