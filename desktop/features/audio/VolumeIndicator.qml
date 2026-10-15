import QtQuick
import "../../ui/Theme.js" as Theme
import "../../ui"

Rectangle {
  id: root
  objectName: "volumeIndicator"

  required property var controller
  signal adjustRequested(real delta)
  readonly property real level: Math.max(0, Math.min(1, controller.volume / 100))
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
    id: volumeIcon
    objectName: "volumeIndicatorIcon"
    anchors.left: parent.left
    anchors.leftMargin: Theme.barSize(15)
    anchors.verticalCenter: parent.verticalCenter
    name: controller.icon()
    color: Theme.sideVolume

  }

  Rectangle {
    id: track
    objectName: "volumeIndicatorTrack"
    anchors.left: volumeIcon.right
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
      color: Theme.sideVolume
    }
  }

  MouseArea {
    anchors.fill: parent
    onWheel: wheel => {
      if (wheel.angleDelta.y > 0)
        root.adjustRequested(root.controller.volumeStep);
      else if (wheel.angleDelta.y < 0)
        root.adjustRequested(-root.controller.volumeStep);
    }
  }
}
