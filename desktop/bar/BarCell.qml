import QtQuick
import "../ui"
import "../ui/Theme.js" as Theme

// A stable hit area inside a shared block. Only the block owns the glass.
Item {
  id: root
  property string text: ""
  property string iconName: ""
  property int textFormat: Text.PlainText
  property int textPixelSize: Theme.barSize(16)
  property color accent: Theme.foreground
  property bool inactive: false
  property bool dimmed: false
  readonly property color contentColor: inactive ? Theme.inactive
    : dimmed ? Qt.alpha(accent, Theme.barDimmedOpacity) : accent
  property bool interactive: false
  property bool forceHovered: false
  property bool iconOnly: false
  property bool circular: false
  property bool outlined: false
  readonly property bool hovered: forceHovered || (interactive && pointer.containsMouse)

  signal leftClicked()
  signal rightClicked()
  signal wheelUp()
  signal wheelDown()

  implicitWidth: iconOnly ? Theme.barSize(32) : Math.max(Theme.barSize(32), content.implicitWidth + Theme.barSize(8))
  implicitHeight: Theme.barSize(circular ? 32 : 28)

  Rectangle {
    objectName: "barCellHighlight"
    anchors.fill: parent
    radius: root.circular ? Math.min(width, height) / 2 : Theme.barSize(9)
    color: root.hovered
      ? Qt.alpha(root.accent, Theme.barSelectionOpacity) : "transparent"
    Behavior on color { ColorAnimation { duration: 160 } }
  }
  Rectangle {
    objectName: "barCellOutline"
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    width: 28 * Theme.barScale
    height: width
    radius: width / 2
    visible: root.outlined
    color: "transparent"
    border.width: Theme.barOutlineWidth
    border.color: root.contentColor
  }
  Row {
    id: content
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    spacing: Theme.barSize(5)
    Icon {
      objectName: "barCellIcon"
      visible: root.iconName !== ""; name: root.iconName; size: Theme.barIconSize
      anchors.verticalCenter: parent.verticalCenter
      color: root.contentColor
    }
    Text {
      id: label
      objectName: "barCellLabel"
      visible: root.text !== ""
      text: root.text; textFormat: root.textFormat
      color: root.contentColor
      font { family: "Ubuntu Nerd Font"; pixelSize: root.textPixelSize; bold: true }
      Behavior on color { ColorAnimation { duration: 220 } }
    }
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) root.rightClicked();
      else root.leftClicked();
    }
    onWheel: wheel => {
      if (wheel.angleDelta.y > 0) root.wheelUp();
      else if (wheel.angleDelta.y < 0) root.wheelDown();
    }
  }
}
