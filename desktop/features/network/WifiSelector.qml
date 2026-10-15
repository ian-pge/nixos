import QtQuick
import "../../ui"
import "../../ui/Layout.js" as Layout
import "../../ui/Theme.js" as Theme

FocusScope {
  id: root
  objectName: "wifiSelector"

  required property var controller
  function uiSize(value) { return controller.speedTestExpanded ? value : Theme.barSize(value); }
  property string spinnerFrame: "loader-circle"
  signal closeRequested()
  readonly property var selectedNetwork: controller.entries.length > 0
    ? controller.entries[Math.min(controller.selectedIndex,
        controller.entries.length - 1)]
    : null
  readonly property string desiredLabelText: {
    if (controller.message !== "") return controller.message;
    if (controller.passwordMode) {
      if (controller.password.length === 0) return "Type password…";
      return "•".repeat(controller.password.length) + " ▏";
    }
    if (controller.loading) return "Scanning for networks…";
    return selectedNetwork !== null ? selectedNetwork.label : "No networks found";
  }
  property string displayedLabelText: ""
  property string previousLabelText: ""
  property bool componentReady: false
  property bool wheelNavigationPending: false
  readonly property string wifiIconText: {
    if (controller.loading) return "loader-circle";
    if (selectedNetwork !== null && selectedNetwork.type === "ethernet")
      return "ethernet-port";
    if (selectedNetwork !== null)
      return signalIcon(selectedNetwork.strength);
    return "wifi-off";
  }
  readonly property string securityIconText:
    !controller.passwordMode && selectedNetwork !== null
      && selectedNetwork.type === "wifi"
      && controller.isSecured(selectedNetwork) ? "lock-keyhole" : ""
  readonly property string counterText: controller.passwordMode ? ""
    : controller.entries.length > 0
      ? (controller.selectedIndex + 1) + "/"
        + controller.entries.length
      : "0/0"
  readonly property real collapsedContentWidth: uiSize(15)
    + uiSize(17) + uiSize(13) + uiSize(7) + uiSize(8)
    + Layout.widestText(labelMetrics,
      [desiredLabelText, displayedLabelText, previousLabelText])
    + uiSize(12) + (securityIconText ? uiSize(13) : 0) + uiSize(8)
    + (controller.passwordMode ? uiSize(13) : counterMetrics.advanceWidth(counterText)) + uiSize(15)

  implicitWidth: controller.speedTestExpanded ? 400
    : Layout.boundedWidth(collapsedContentWidth, 0, uiSize(400))
  implicitHeight: controller.speedTestExpanded ? 94 : uiSize(36)

  FontMetrics {
    id: labelMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: root.uiSize(14)
    font.bold: true
  }

  FontMetrics {
    id: counterMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: root.uiSize(12)
    font.bold: true
  }

  function signalIcon(strength) {
    if (strength < 26) return "wifi-zero";
    if (strength < 51) return "wifi-low";
    if (strength < 76) return "wifi-high";
    return "wifi";
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
    incomingSlide.y = controller.selectionDirection > 0 ? uiSize(40) : -uiSize(40);
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
    if (!wheelNavigationPending || !enabled || controller.passwordMode
        || controller.loading || controller.message !== "")
      syncLabel();
    else
      animateLabel();
  }

  onEnabledChanged: {
    if (enabled)
      Qt.callLater(() => root.forceActiveFocus());
  }

  Keys.onPressed: event => {
    if (controller.passwordMode) {
      if (event.key === Qt.Key_Escape) {
        controller.cancelPassword();
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        controller.connectSelected();
      } else if (event.key === Qt.Key_Backspace) {
        controller.erasePassword();
      } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
        controller.password = "";
        controller.message = "";
      } else if (event.text.length > 0
          && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        controller.appendPassword(event.text);
      }
      event.accepted = true;
      return;
    }

    if (event.key === Qt.Key_J || event.key === Qt.Key_Down
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
    } else if (event.key === Qt.Key_G && !(event.modifiers & Qt.ShiftModifier)) {
      wheelNavigationPending = true;
      controller.setSelection(0, -1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
      wheelNavigationPending = true;
      controller.setSelection(
        Math.max(0, controller.entries.length - 1), 1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_T) {
      controller.startSpeedTest();
      event.accepted = true;
    } else if (event.key === Qt.Key_R) {
      controller.refresh();
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      controller.connectSelected();
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
      root.closeRequested();
      event.accepted = true;
    }
  }

  Item {
    id: networkRow
    objectName: "wifiSelectorRow"
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.uiSize(36)

  Icon {

    size: root.uiSize(17)
    id: wifiIcon
    objectName: "wifiSelectorIcon"
    anchors.left: parent.left
    anchors.leftMargin: root.uiSize(15)
    anchors.verticalCenter: parent.verticalCenter
    name: root.wifiIconText
    spinning: controller.loading
    color: Theme.sideNetwork

  }

  Rectangle {
    id: activeDot
    anchors.left: wifiIcon.right
    anchors.leftMargin: root.uiSize(13)
    anchors.verticalCenter: parent.verticalCenter
    width: root.uiSize(7)
    height: root.uiSize(7)
    radius: root.uiSize(3.5)
    color: root.selectedNetwork !== null && root.selectedNetwork.active
      ? Theme.sideNetwork : Theme.inactive
  }

  Item {
    id: labelViewport
    anchors.left: activeDot.right
    anchors.leftMargin: root.uiSize(8)
    anchors.right: wifiStatus.left
    anchors.rightMargin: root.uiSize(12)
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
      font.pixelSize: root.uiSize(14)
      font.bold: true
    }

    Text {
      id: incomingLabel
      objectName: "wifiSelectorLabel"
      text: root.displayedLabelText
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      transform: Translate { id: incomingSlide }
      color: Theme.foreground
      elide: Text.ElideNone
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(14)
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
      to: controller.selectionDirection > 0 ? -root.uiSize(40) : root.uiSize(40)
      duration: 150
      easing.type: Easing.InOutCubic
    }

    NumberAnimation {
      target: incomingSlide
      property: "y"
      from: controller.selectionDirection > 0 ? root.uiSize(40) : -root.uiSize(40)
      to: 0
      duration: 150
      easing.type: Easing.InOutCubic
    }
  }

  Row {
    id: wifiStatus
    anchors.right: parent.right
    anchors.rightMargin: root.uiSize(15)
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.uiSize(8)

    Icon {

      size: root.uiSize(13)
      name: root.securityIconText
      visible: name !== ""
      height: root.uiSize(18)

      color: Theme.secondary

    }

    Text {
      text: root.counterText
      visible: !controller.passwordMode
      height: root.uiSize(18)
      verticalAlignment: Text.AlignVCenter
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(12)
      font.bold: true
    }
    Icon { name: "lock-keyhole"; size: root.uiSize(13); color: Theme.secondary; visible: controller.passwordMode }
  }
  }

  Item {
    id: speedTestPanel
    anchors.top: networkRow.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(0, root.height - networkRow.height)
    visible: controller.speedTestExpanded
    opacity: visible ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 180 } }

    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.uiSize(14)
      anchors.rightMargin: root.uiSize(14)
      height: root.uiSize(1)
      color: Theme.surfaceRaised
    }

    Item {
      visible: controller.speedTestRunning
      anchors.fill: parent

      Icon {
        id: speedTestSpinner
        anchors.left: parent.left
        anchors.leftMargin: root.uiSize(15)
        y: root.uiSize(8)
        name: root.spinnerFrame; spinning: true
        color: Theme.sideNetwork
        size: root.uiSize(15)

      }

      Text {
        anchors.left: speedTestSpinner.right
        anchors.leftMargin: root.uiSize(8)
        y: root.uiSize(8)
        text: controller.speedTestPhase
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: root.uiSize(11)
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.uiSize(8)
        text: controller.speedTestLiveValue
        color: Theme.sideNetwork
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: root.uiSize(11)
        font.bold: true
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: root.uiSize(15)
        y: root.uiSize(8)
        text: Math.round(controller.speedTestProgress * 100) + "%"
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: root.uiSize(11)
        font.bold: true
      }

      Rectangle {
        id: speedTestProgressTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.uiSize(15)
        anchors.rightMargin: root.uiSize(15)
        y: root.uiSize(35)
        height: root.uiSize(5)
        radius: root.uiSize(2.5)
        color: Theme.surfaceRaised

        Rectangle {
          width: parent.width * controller.speedTestProgress
          height: parent.height
          radius: parent.radius
          color: Theme.sideNetwork

          Behavior on width {
            NumberAnimation {
              duration: 180
              easing.type: Easing.OutCubic
            }
          }
        }
      }
    }

    Row {
      id: speedMetrics
      visible: controller.speedTestHasResult
        && !controller.speedTestRunning
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.uiSize(14)
      anchors.rightMargin: root.uiSize(14)

      Repeater {
        model: [
          { "label": "PING", "value": controller.speedTestPing,
            "unit": "ms" },
          { "label": "DOWN", "value": controller.speedTestDownload,
            "unit": "Mb/s" },
          { "label": "UP", "value": controller.speedTestUpload,
            "unit": "Mb/s" }
        ]

        Item {
          required property var modelData
          width: speedMetrics.width / 3
          height: speedMetrics.height

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.uiSize(8)
            text: modelData.label
            color: Theme.secondary
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: root.uiSize(10)
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.uiSize(25)
            text: modelData.value + " " + modelData.unit
            color: Theme.sideNetwork
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: root.uiSize(12)
            font.bold: true
          }
        }
      }
    }

    Text {
      visible: !controller.speedTestRunning
        && !controller.speedTestHasResult
      anchors.centerIn: parent
      text: controller.speedTestMessage
      color: Theme.error
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: root.uiSize(12)
      font.bold: true
    }
  }
}
