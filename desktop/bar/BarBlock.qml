import QtQuick
import Local.LiquidGlass
import "../ui"
import "../ui/Theme.js" as Theme

Item {
  id: root
  default property alias content: body.data
  property color accent: Theme.foreground
  property bool outlined: false
  property bool forceHovered: false
  property bool interactive: false
  readonly property bool hovered: forceHovered || (interactive && pointer.containsMouse)
  property bool circularContent: false
  signal leftClicked()
  // Match horizontal and vertical insets so the end dials share the centers
  // of the capsule's semicircles. A single dial then has a circular backdrop.
  readonly property real horizontalPadding: circularContent ? Math.max(0, (height - body.height) / 2) : Theme.barSize(8)

  implicitWidth: body.childrenRect.width + 2 * horizontalPadding
  implicitHeight: Theme.barSize(36)

  Rectangle {
    objectName: "barBlockBackground"
    anchors.fill: parent
    radius: height / 2
    color: GlassState.enabled
      ? Qt.alpha(Theme.background, 0.12) : Theme.background
    GlassShape { anchors.fill: parent; radius: parent.radius; enabled: GlassState.enabled }
    Behavior on color { ColorAnimation { duration: 220 } }
  }
  Rectangle {
    objectName: "barBlockSelection"
    anchors.fill: parent
    anchors.margins: Theme.barSelectionInset()
    radius: height / 2
    color: root.hovered ? Qt.alpha(root.accent, Theme.barSelectionOpacity) : "transparent"
    Behavior on color { ColorAnimation { duration: 160 } }
  }

  Rectangle {
    objectName: "barBlockOutline"
    anchors.fill: parent
    anchors.margins: Theme.barOutlineInset()
    visible: root.outlined
    radius: height / 2
    color: "transparent"
    border.width: Theme.barOutlineWidth
    border.color: root.accent
  }

  Item {
    id: body
    anchors.centerIn: parent
    anchors.alignWhenCentered: false
    width: childrenRect.width
    height: childrenRect.height
  }
  MouseArea {
    id: pointer
    objectName: "barBlockPointer"
    parent: root
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: root.leftClicked()
  }
}
