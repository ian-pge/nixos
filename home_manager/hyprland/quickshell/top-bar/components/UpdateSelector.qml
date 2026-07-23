import QtQuick
import "Theme.js" as Theme

FocusScope {
  id: root

  required property var statusData
  readonly property var updates: statusData.nixUpdates
  readonly property int rowCount: Math.max(1, updates.length)
  implicitWidth: 480
  implicitHeight: 52 + rowCount * 30 + 10

  onEnabledChanged: {
    if (enabled)
      Qt.callLater(() => root.forceActiveFocus());
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_R) {
      statusData.forceNixStatus();
      event.accepted = true;
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      statusData.startNixUpdate();
      event.accepted = true;
    } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
      statusData.hideUpdateSelector();
      event.accepted = true;
    }
  }

  Item {
    anchors.fill: parent

    Text {
      id: updateIcon
      anchors.left: parent.left
      anchors.leftMargin: 16
      y: 9
      width: 20
      height: 20
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: statusData.nixChecking ? "󰑐" : updates.length > 0 ? "" : ""
      color: statusData.nixChecking ? Theme.state
        : updates.length > 0 ? Theme.action : Theme.inactive
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true

      RotationAnimator on rotation {
        running: statusData.nixChecking
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        onStopped: updateIcon.rotation = 0
      }
    }

    Text {
      anchors.left: updateIcon.right
      anchors.leftMargin: 10
      y: 8
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: statusData.nixChecking ? "Checking for updates…" : "NixOS updates"
      color: Theme.foreground
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: 16
      y: 9
      height: 20
      verticalAlignment: Text.AlignVCenter
      text: statusData.nixChecking ? "CHECKING"
        : updates.length > 0 ? updates.length + " AVAILABLE" : "UP TO DATE"
      color: statusData.nixChecking || updates.length > 0
        ? Theme.state : Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 11
      font.bold: true
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      y: 40
      height: 1
      color: Theme.surfaceRaised
    }

    Item {
      id: updateViewport
      anchors.left: parent.left
      anchors.right: parent.right
      y: 42
      height: Math.max(0, root.height - y)
      clip: true

      Column {
        id: updateRows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        y: 6
        spacing: 0

        Repeater {
          model: root.updates

          Item {
            required property var modelData
            width: updateRows.width
            height: 30

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: 7
              height: 7
              radius: 3.5
              color: Theme.state
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 16
              anchors.right: updateDate.left
              anchors.rightMargin: 16
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.name
              color: Theme.foreground
              elide: Text.ElideRight
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 13
              font.bold: true
            }

            Text {
              id: updateDate
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.date
              color: Theme.secondary
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 12
              font.bold: true
            }
          }
        }
      }

      Text {
        visible: root.updates.length === 0
        anchors.left: parent.left
        anchors.right: parent.right
        y: 6
        height: 30
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: statusData.nixChecking ? "Refreshing the cached update list…"
          : statusData.nixTooltip === "Unable to check for updates"
            ? statusData.nixTooltip : "System is up to date"
        color: statusData.nixTooltip === "Unable to check for updates"
          ? Theme.error : Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 13
        font.bold: true
      }
    }
  }
}
