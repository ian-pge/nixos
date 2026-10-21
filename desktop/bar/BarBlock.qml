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
  // Keep the dial inset constant as a grid grows vertically. A single dial
  // still has a circular backdrop; larger groups keep rounded corners.
  readonly property real horizontalPadding: circularContent ? (Theme.barSize(36) - Theme.barSize(32)) / 2 : Theme.barSize(8)

  implicitWidth: body.childrenRect.width + 2 * horizontalPadding
  implicitHeight: Math.max(Theme.barSize(36), body.childrenRect.height + 2 * horizontalPadding)

  Rectangle {
    objectName: "barBlockBackground"
    anchors.fill: parent
    radius: Math.min(Theme.barSize(18), width / 2, height / 2)
    color: GlassState.enabled
      ? Qt.alpha(Theme.background, 0.12) : Theme.background
    GlassShape { anchors.fill: parent; radius: parent.radius; enabled: GlassState.enabled }
    Behavior on color { ColorAnimation { duration: 220 } }
  }
  Rectangle {
    objectName: "barBlockSelection"
    anchors.fill: parent
    anchors.margins: Theme.barSelectionInset()
    radius: Math.min(Theme.barSize(18) - Theme.barSelectionInset(), width / 2, height / 2)
    color: root.hovered ? Qt.alpha(root.accent, Theme.barSelectionOpacity) : "transparent"
    Behavior on color { ColorAnimation { duration: 160 } }
  }

  Rectangle {
    objectName: "barBlockOutline"
    anchors.fill: parent
    anchors.margins: Theme.barOutlineInset()
    visible: root.outlined
    radius: Math.min(Theme.barSize(18) - Theme.barOutlineInset(), width / 2, height / 2)
    color: "transparent"
    border.width: Theme.barOutlineWidth
    border.color: root.accent
  }

  Item {
    id: body
    // Arithmetic centering preserves half-pixel insets at fractional scales.
    x: (root.width - width) / 2
    y: (root.height - height) / 2
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
