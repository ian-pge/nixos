import QtQuick

Rectangle {
  id: root

  required property var statusData
  readonly property real level: Math.max(0, Math.min(1, statusData.audioVolume / 100))
  property real displayedLevel: level

  implicitWidth: 280
  implicitHeight: 36
  radius: 18
  color: "#181926"

  onLevelChanged: iconPulse.restart()

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
    color: statusData.audioMuted ? "#ed8796" : "#b7bdf8"
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
      color: statusData.audioMuted ? "#ed8796" : "#b7bdf8"

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

  SequentialAnimation {
    id: iconPulse
    NumberAnimation {
      target: volumeIcon
      property: "scale"
      to: 1.22
      duration: 90
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: volumeIcon
      property: "scale"
      to: 1
      duration: 150
      easing.type: Easing.OutBack
    }
  }

  MouseArea {
    anchors.fill: parent
    onWheel: wheel => {
      if (wheel.angleDelta.y > 0)
        statusData.setVolume(0.02);
      else if (wheel.angleDelta.y < 0)
        statusData.setVolume(-0.02);
      statusData.showVolumeOverlay();
    }
  }
}
