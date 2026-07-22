import QtQuick

Rectangle {
  id: root

  required property var statusData
  property string targetMonitor: ""
  readonly property real level: Math.max(0, Math.min(1, statusData.audioVolume / 100))
  property real displayedLevel: level

  implicitWidth: 280
  implicitHeight: 36
  radius: 18
  color: "#181926"

  Behavior on displayedLevel {
    NumberAnimation {
      duration: 140
      easing.type: Easing.OutCubic
    }
  }

  Text {
    id: volumeIcon
    anchors.left: parent.left
    anchors.leftMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    text: statusData.audioIcon()
    color: statusData.audioMuted ? "#ffcc33" : "#ff33cc"
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 17
    font.bold: true

    Behavior on color {
      ColorAnimation { duration: 180 }
    }
  }

  Rectangle {
    id: track
    anchors.left: volumeIcon.right
    anchors.leftMargin: 13
    anchors.right: parent.right
    anchors.rightMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    height: 8
    radius: 4
    color: "#363a4f"

    Rectangle {
      id: fill
      width: track.width * root.displayedLevel
      height: parent.height
      radius: 4
      color: statusData.audioMuted ? "#ffcc33" : "#ff33cc"

      Behavior on color {
        ColorAnimation { duration: 180 }
      }
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(0, Math.min(track.width - width, fill.width - width / 2))
      width: 12
      height: 12
      radius: 6
      color: "#cad3f5"
    }
  }

  MouseArea {
    anchors.fill: parent
    onWheel: wheel => {
      if (wheel.angleDelta.y > 0)
        statusData.setVolume(0.02);
      else if (wheel.angleDelta.y < 0)
        statusData.setVolume(-0.02);
      statusData.showVolumeOverlay(root.targetMonitor);
    }
  }
}
