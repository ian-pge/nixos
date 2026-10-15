import QtQuick
import "../../ui/Theme.js" as Theme
import "../../ui"

Rectangle {
  id: root
  objectName: "brightnessIndicator"

  required property var controller
  property string targetMonitor: ""
  signal changeRequested(int delta)
  readonly property real level: Math.max(0, Math.min(1, (controller.value(targetMonitor) ?? 0) / 100))
  property real displayedLevel: level

  implicitWidth: Theme.barSize(280)
  implicitHeight: Theme.barSize(36)
  radius: Theme.barSize(18)
  color: GlassState.enabled ? "transparent" : Theme.background

  Behavior on displayedLevel {
    NumberAnimation {
      duration: 140
      easing.type: Easing.OutCubic
    }
  }

  Icon {

    size: Theme.barSize(17)
    id: brightnessIcon
    objectName: "brightnessIndicatorIcon"
    anchors.left: parent.left
    anchors.leftMargin: Theme.barSize(15)
    anchors.verticalCenter: parent.verticalCenter
    name: controller.icon(targetMonitor)
    color: Theme.sideBrightness

  }

  Rectangle {
    id: track
    anchors.left: brightnessIcon.right
    anchors.leftMargin: Theme.barSize(13)
    anchors.right: parent.right
    anchors.rightMargin: Theme.barSize(15)
    anchors.verticalCenter: parent.verticalCenter
    height: Theme.barSize(8)
    radius: Theme.barSize(4)
    color: Theme.surfaceRaised

    Rectangle {
      id: fill
      width: track.width * root.displayedLevel
      height: parent.height
      radius: Theme.barSize(4)
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
