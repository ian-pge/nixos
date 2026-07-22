import Quickshell.Io
import QtQuick

Rectangle {
  id: root

  required property var statusData
  readonly property real level: Math.max(0, Math.min(1, statusData.brightness / 100))
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
    id: brightnessIcon
    anchors.left: parent.left
    anchors.leftMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    text: statusData.brightnessIcon()
    color: "#eed49f"
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 17
    font.bold: true
  }

  Rectangle {
    id: track
    anchors.left: brightnessIcon.right
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
      color: "#eed49f"
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
      target: brightnessIcon
      property: "scale"
      to: 1.22
      duration: 90
      easing.type: Easing.OutCubic
    }
    NumberAnimation {
      target: brightnessIcon
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
        brightnessUp.startDetached();
      else if (wheel.angleDelta.y < 0)
        brightnessDown.startDetached();
      statusData.showBrightnessOverlay();
    }
  }

  Process {
    id: brightnessUp
    command: ["brightnessctl", "set", "+5%"]
  }

  Process {
    id: brightnessDown
    command: ["brightnessctl", "set", "5%-"]
  }
}
