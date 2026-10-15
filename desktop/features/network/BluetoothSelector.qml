import QtQuick
import "../../ui"
import "../../ui/Layout.js" as Layout
import "../../ui/Theme.js" as Theme

FocusScope {
  id: root
  objectName: "bluetoothSelector"

  required property var controller
  property string spinnerFrame: "loader-circle"
  signal closeRequested()
  readonly property var devices: controller.currentDevices
  readonly property var selectedDevice: devices.length > 0
    ? devices[Math.min(controller.selectedIndex, devices.length - 1)]
    : null
  readonly property bool selectedDeviceConnected: selectedDevice !== null
    && selectedDevice.connected
  readonly property string desiredLabelText: {
    if (controller.message !== "")
      return controller.message;
    if (controller.loading)
      return controller.tab === 0 ? "Loading paired devices…" : "Scanning nearby devices…";
    return selectedDevice !== null ? selectedDevice.name : "No devices found";
  }

  property string displayedLabelText: ""
  property string previousLabelText: ""
  property bool componentReady: false
  property bool wheelNavigationPending: false
  readonly property string bluetoothIconText:
    controller.scanning ? "loader-circle"
      : selectedDeviceConnected ? "bluetooth-connected" : "bluetooth-off"
  readonly property string tabText: controller.tab === 0
    ? "PAIRED" : "NEARBY"
  readonly property string counterText: devices.length > 0
    ? (controller.selectedIndex + 1) + "/" + devices.length : "0/0"
  readonly property real contentWidth: Theme.barSize(15)
    + Theme.barSize(17) + Theme.barSize(13) + Theme.barSize(7) + Theme.barSize(8)
    + Layout.widestText(labelMetrics,
      [desiredLabelText, displayedLabelText, previousLabelText])
    + Theme.barSize(12) + tabMetrics.advanceWidth(tabText) + Theme.barSize(8)
    + counterMetrics.advanceWidth(counterText) + Theme.barSize(15)

  implicitWidth: Layout.boundedWidth(contentWidth, 0, Theme.barSize(400))
  implicitHeight: Theme.barSize(36)

  FontMetrics {
    id: labelMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: Theme.barSize(14)
    font.bold: true
  }

  FontMetrics {
    id: tabMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: Theme.barSize(11)
    font.bold: true
  }

  FontMetrics {
    id: counterMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: Theme.barSize(12)
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
    incomingSlide.y = controller.selectionDirection > 0 ? Theme.barSize(40) : -Theme.barSize(40);
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
    if (!wheelNavigationPending || !enabled || controller.loading
        || controller.message !== "")
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
      controller.switchTab();
      event.accepted = true;
    } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down
        || event.key === Qt.Key_L || event.key === Qt.Key_Right) {
      wheelNavigationPending = true;
      controller.moveSelection(1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up
        || event.key === Qt.Key_H || event.key === Qt.Key_Left) {
      wheelNavigationPending = true;
      controller.moveSelection(-1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_R) {
      controller.refresh(controller.tab === 1);
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      controller.activateSelected();
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
      root.closeRequested();
      event.accepted = true;
    }
  }

  Icon {

    size: Theme.barSize(17)
    id: bluetoothIcon
    objectName: "bluetoothSelectorIcon"
    anchors.left: parent.left
    anchors.leftMargin: Theme.barSize(15)
    anchors.verticalCenter: parent.verticalCenter
    name: root.bluetoothIconText
    spinning: controller.scanning
    color: Theme.sideBluetooth

  }

  Rectangle {
    id: activeDot
    anchors.left: bluetoothIcon.right
    anchors.leftMargin: Theme.barSize(13)
    anchors.verticalCenter: parent.verticalCenter
    width: Theme.barSize(7)
    height: Theme.barSize(7)
    radius: Theme.barSize(3.5)
    color: root.selectedDeviceConnected ? Theme.sideBluetooth : Theme.inactive
  }

  Item {
    id: labelViewport
    anchors.left: activeDot.right
    anchors.leftMargin: Theme.barSize(8)
    anchors.right: bluetoothStatus.left
    anchors.rightMargin: Theme.barSize(12)
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
      font.pixelSize: Theme.barSize(14)
      font.bold: true
    }

    Text {
      id: incomingLabel
      objectName: "bluetoothSelectorLabel"
      text: root.displayedLabelText
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      transform: Translate { id: incomingSlide }
      color: Theme.foreground
      elide: Text.ElideNone
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: Theme.barSize(14)
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
      to: controller.selectionDirection > 0 ? -Theme.barSize(40) : Theme.barSize(40)
      duration: 150
      easing.type: Easing.InOutCubic
    }

    NumberAnimation {
      target: incomingSlide
      property: "y"
      from: controller.selectionDirection > 0 ? Theme.barSize(40) : -Theme.barSize(40)
      to: 0
      duration: 150
      easing.type: Easing.InOutCubic
    }
  }

  Row {
    id: bluetoothStatus
    anchors.right: parent.right
    anchors.rightMargin: Theme.barSize(15)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.barSize(8)

    Text {
      text: root.tabText
      height: Theme.barSize(18)
      verticalAlignment: Text.AlignVCenter
      color: Theme.sideBluetooth
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: Theme.barSize(11)
      font.bold: true
    }

    Text {
      text: root.counterText
      height: Theme.barSize(18)
      verticalAlignment: Text.AlignVCenter
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: Theme.barSize(12)
      font.bold: true
    }
  }
}
