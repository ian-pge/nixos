import Quickshell.Io
import QtQuick
import "Theme.js" as Theme

Rectangle {
  id: root

  required property var statusData
  property string targetMonitor: ""
  readonly property real level: Math.max(0, Math.min(1, statusData.brightness / 100))
  property real displayedLevel: level

  implicitWidth: 280
  implicitHeight: 36
  radius: 18
  color: Theme.background

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
    color: Theme.sideBrightness
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
    color: Theme.surfaceRaised

    Rectangle {
      id: fill
      width: track.width * root.displayedLevel
      height: parent.height
      radius: 4
      color: Theme.sideBrightness
    }
  }

  MouseArea {
    anchors.fill: parent
    onWheel: wheel => {
      if (wheel.angleDelta.y > 0)
        brightnessUp.startDetached();
      else if (wheel.angleDelta.y < 0)
        brightnessDown.startDetached();
      statusData.showBrightnessOverlay(root.targetMonitor);
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
