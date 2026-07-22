import QtQuick

FocusScope {
  id: root

  required property var statusData
  readonly property var selectedNetwork: statusData.wifiNetworks.length > 0
    ? statusData.wifiNetworks[Math.min(statusData.wifiSelectedIndex,
        statusData.wifiNetworks.length - 1)]
    : null
  readonly property string desiredLabelText: {
    if (statusData.wifiMessage !== "") return statusData.wifiMessage;
    if (statusData.wifiPasswordMode) {
      if (statusData.wifiPassword.length === 0) return "Type password…";
      return "•".repeat(statusData.wifiPassword.length) + " ▏";
    }
    if (statusData.wifiLoading) return "Scanning for networks…";
    return selectedNetwork !== null ? selectedNetwork.ssid : "No networks found";
  }
  property string displayedLabelText: ""
  property bool componentReady: false
  property bool wheelNavigationPending: false

  implicitWidth: 400
  implicitHeight: 36

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
        Math.max(0, statusData.wifiNetworks.length - 1), 1);
      wheelNavigationPending = false;
      event.accepted = true;
    } else if (event.key === Qt.Key_R) {
      statusData.refreshWifiNetworks(true);
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      statusData.connectSelectedWifi();
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
      statusData.hideWifiSelector();
      event.accepted = true;
    }
  }

  Text {
    id: wifiIcon
    anchors.left: parent.left
    anchors.leftMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    text: {
      if (statusData.wifiLoading) return "󰑐";
      if (root.selectedNetwork !== null)
        return root.signalIcon(root.selectedNetwork.strength);
      return "󰤭";
    }
    color: "#ff33cc"
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
      ? "#ffcc33" : "#6e738d"
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
        && root.selectedNetwork.security !== ""
        && root.selectedNetwork.security !== "--" ? "󰌾" : ""
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: "#939ab7"
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 13
    }

    Text {
      text: statusData.wifiPasswordMode ? "󰌾"
        : statusData.wifiNetworks.length > 0
          ? (statusData.wifiSelectedIndex + 1) + "/" + statusData.wifiNetworks.length
          : "0/0"
      height: 18
      verticalAlignment: Text.AlignVCenter
      color: "#939ab7"
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 12
      font.bold: true
    }
  }
}
