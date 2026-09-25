import QtQuick
import QtQuick.Controls
import "Theme.js" as Theme

Button {
  id: root
  property bool prominent: false
  property color accent: Theme.sideApplications
  implicitHeight: 42
  implicitWidth: Math.max(42, contentItem.implicitWidth + 26)
  focusPolicy: Qt.TabFocus
  font.family: "Ubuntu Nerd Font"
  font.pixelSize: Theme.beeperFont.control
  padding: 10
  background: Rectangle {
    radius: 10
    color: root.down ? Qt.alpha(root.accent, 0.3) : root.prominent ? Qt.alpha(root.accent, 0.18) : root.hovered || root.activeFocus ? Qt.alpha(Theme.foreground, 0.09) : "transparent"
    border.width: root.activeFocus ? 1 : 0
    border.color: Qt.alpha(root.accent, 0.65)
  }
  contentItem: Text {
    text: root.text; font: root.font; color: !root.enabled ? Theme.inactive : root.prominent ? root.accent : Theme.foreground
    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
  }
}
