import QtQuick
import "../../ui/Theme.js" as Theme
import "../../ui"

Rectangle {
  id: root

  required property var controller
  property string targetMonitor: ""
  signal changeRequested(int delta)
  readonly property real level: Math.max(0, Math.min(1, controller.value(targetMonitor) / 100))
  property real displayedLevel: level

  implicitWidth: 280
  implicitHeight: 36
  radius: 18
  color: GlassState.enabled ? "transparent" : Theme.background

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
    text: controller.icon(targetMonitor)
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
        root.changeRequested(5);
      else if (wheel.angleDelta.y < 0)
        root.changeRequested(-5);
    }
  }
}
