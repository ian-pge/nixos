import QtQuick
import "Theme.js" as Theme

FocusScope {
  id: root

  required property var statusData
  readonly property var selectedNetwork: statusData.networkSelectorEntries.length > 0
    ? statusData.networkSelectorEntries[Math.min(statusData.wifiSelectedIndex,
        statusData.networkSelectorEntries.length - 1)]
    : null
  readonly property string desiredLabelText: {
    if (statusData.wifiMessage !== "") return statusData.wifiMessage;
    if (statusData.wifiPasswordMode) {
      if (statusData.wifiPassword.length === 0) return "Type password…";
      return "•".repeat(statusData.wifiPassword.length) + " ▏";
    }
    if (statusData.wifiLoading) return "Scanning for networks…";
    return selectedNetwork !== null ? selectedNetwork.label : "No networks found";
  }
  property string displayedLabelText: ""
  property bool componentReady: false
  property bool wheelNavigationPending: false

  implicitWidth: 400
  implicitHeight: statusData.wifiSpeedTestExpanded ? 94 : 36

  function signalIcon(strength) {
    if (strength < 26) return "󰤟";
    if (strength < 51) return "󰤢";
    if (strength < 76) return "󰤥";
    return "󰤨";
  }

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
    incomingSlide.y = statusData.wifiSelectionDirection > 0 ? 40 : -40;
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
    if (!wheelNavigationPending || !enabled || statusData.wifiPasswordMode
        || statusData.wifiLoading || statusData.wifiMessage !== "")
      syncLabel();
    else
      animateLabel();
  }

  onEnabledChanged: {
    if (enabled)
      Qt.callLater(() => root.forceActiveFocus());
  }

  Keys.onPressed: event => {
    if (statusData.wifiPasswordMode) {
      if (event.key === Qt.Key_Escape) {
        statusData.cancelWifiPassword();
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        statusData.connectSelectedWifi();
      } else if (event.key === Qt.Key_Backspace) {
        statusData.eraseWifiPassword();
      } else if (event.key === Qt.Key_U && (event.modifiers & Qt.ControlModifier)) {
        statusData.wifiPassword = "";
        statusData.wifiMessage = "";
      } else if (event.text.length > 0
          && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        statusData.appendWifiPassword(event.text);
      }
      event.accepted = true;
      return;
    }

    if (event.key === Qt.Key_J || event.key === Qt.Key_Down
        || event.key === Qt.Key_L || event.key === Qt.Key_Right) {
      wheelNavigationPending = true;
      statusData.moveWifiSelection(1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up
        || event.key === Qt.Key_H || event.key === Qt.Key_Left) {
      wheelNavigationPending = true;
      statusData.moveWifiSelection(-1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_G && !(event.modifiers & Qt.ShiftModifier)) {
      wheelNavigationPending = true;
      statusData.setWifiSelection(0, -1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
      wheelNavigationPending = true;
      statusData.setWifiSelection(
        Math.max(0, statusData.networkSelectorEntries.length - 1), 1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_T) {
      statusData.startWifiSpeedTest();
      event.accepted = true;
    } else if (event.key === Qt.Key_R) {
      statusData.refreshWifiNetworks();
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      statusData.connectSelectedWifi();
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
      statusData.hideWifiSelector();
      event.accepted = true;
    }
  }

  Item {
    id: networkRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 36

  Text {
    id: wifiIcon
    anchors.left: parent.left
    anchors.leftMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    text: {
      if (statusData.wifiLoading) return "󰑐";
      if (root.selectedNetwork !== null
          && root.selectedNetwork.type === "ethernet")
        return "󰈀";
      if (root.selectedNetwork !== null)
        return root.signalIcon(root.selectedNetwork.strength);
      return "󰤭";
    }
    color: Theme.sideNetwork
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 17
    font.bold: true

    RotationAnimator on rotation {
      running: statusData.wifiLoading
      from: 0
      to: 360
      duration: 900
      loops: Animation.Infinite
      onStopped: wifiIcon.rotation = 0
    }
  }

  Rectangle {
    id: activeDot
    anchors.left: wifiIcon.right
    anchors.leftMargin: 13
    anchors.verticalCenter: parent.verticalCenter
    width: 7
    height: 7
    radius: 3.5
    color: root.selectedNetwork !== null && root.selectedNetwork.active
      ? Theme.sideNetwork : Theme.inactive
  }

  Item {
    id: labelViewport
    anchors.left: activeDot.right
    anchors.leftMargin: 8
    anchors.right: wifiStatus.left
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
      color: Theme.foreground
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
      color: Theme.foreground
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
      to: statusData.wifiSelectionDirection > 0 ? -40 : 40
      duration: 150
      easing.type: Easing.InOutCubic
    }

    NumberAnimation {
      target: incomingSlide
      property: "y"
      from: statusData.wifiSelectionDirection > 0 ? 40 : -40
      to: 0
      duration: 150
      easing.type: Easing.InOutCubic
    }
  }

  Row {
    id: wifiStatus
    anchors.right: parent.right
    anchors.rightMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8

    Text {
      text: !statusData.wifiPasswordMode && root.selectedNetwork !== null
        && root.selectedNetwork.type === "wifi"
        && root.selectedNetwork.security !== ""
        && root.selectedNetwork.security !== "--" ? "󰌾" : ""
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 13
    }

    Text {
      text: statusData.wifiPasswordMode ? "󰌾"
        : statusData.networkSelectorEntries.length > 0
          ? (statusData.wifiSelectedIndex + 1) + "/"
            + statusData.networkSelectorEntries.length
          : "0/0"
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 12
      font.bold: true
    }
  }
  }

  Item {
    id: speedTestPanel
    anchors.top: networkRow.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: Math.max(0, root.height - networkRow.height)
    visible: statusData.wifiSpeedTestExpanded
    opacity: visible ? 1 : 0

    Behavior on opacity { NumberAnimation { duration: 180 } }

    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      height: 1
      color: Theme.surfaceRaised
    }

    Item {
      visible: statusData.wifiSpeedTestRunning
      anchors.fill: parent

      Text {
        id: speedTestSpinner
        anchors.left: parent.left
        anchors.leftMargin: 15
        y: 8
        text: "󰑐"
        color: Theme.sideNetwork
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 15
        font.bold: true

        RotationAnimator on rotation {
          running: statusData.wifiSpeedTestRunning
          from: 0
          to: 360
          duration: 900
          loops: Animation.Infinite
          onStopped: speedTestSpinner.rotation = 0
        }
      }

      Text {
        anchors.left: speedTestSpinner.right
        anchors.leftMargin: 8
        y: 8
        text: statusData.wifiSpeedTestPhase
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 11
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        text: statusData.wifiSpeedTestLiveValue
        color: Theme.sideNetwork
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 11
        font.bold: true
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: 15
        y: 8
        text: Math.round(statusData.wifiSpeedTestProgress * 100) + "%"
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 11
        font.bold: true
      }

      Rectangle {
        id: speedTestProgressTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 15
        anchors.rightMargin: 15
        y: 35
        height: 5
        radius: 2.5
        color: Theme.surfaceRaised

        Rectangle {
          width: parent.width * statusData.wifiSpeedTestProgress
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
      visible: statusData.wifiSpeedTestHasResult
        && !statusData.wifiSpeedTestRunning
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 14
      anchors.rightMargin: 14

      Repeater {
        model: [
          { "label": "PING", "value": statusData.wifiSpeedTestPing,
            "unit": "ms" },
          { "label": "DOWN", "value": statusData.wifiSpeedTestDownload,
            "unit": "Mb/s" },
          { "label": "UP", "value": statusData.wifiSpeedTestUpload,
            "unit": "Mb/s" }
        ]

        Item {
          required property var modelData
          width: speedMetrics.width / 3
          height: speedMetrics.height

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            text: modelData.label
            color: Theme.secondary
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 10
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 25
            text: modelData.value + " " + modelData.unit
            color: Theme.sideNetwork
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 12
            font.bold: true
          }
        }
      }
    }

    Text {
      visible: !statusData.wifiSpeedTestRunning
        && !statusData.wifiSpeedTestHasResult
      anchors.centerIn: parent
      text: statusData.wifiSpeedTestMessage
      color: Theme.error
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 12
      font.bold: true
    }
  }
}
