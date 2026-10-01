import QtQuick
import QtQuick.Controls
import "../../ui"
import "../../ui/Theme.js" as Theme

Button {
  id: root
  property bool prominent: false
  property color accent: Theme.sideApplications
  property string iconName: ""
  property real iconSize: 18
  implicitHeight: 42
  implicitWidth: Math.max(42, contentItem.implicitWidth + 26)
  focusPolicy: Qt.TabFocus
  font.family: "Ubuntu Nerd Font"
  font.pixelSize: Theme.beeperFont.control
  padding: 10
  background: Rectangle {
    radius: 10
    color: root.down ? Qt.alpha(root.accent, 0.3) : root.prominent ? Qt.alpha(root.accent, 0.18) : root.hovered || root.activeFocus ? Qt.alpha(Theme.foreground, 0.09) : "transparent"
  }
  contentItem: Item {
    implicitWidth: textLabel.implicitWidth + (root.iconName ? root.iconSize + (root.text ? 6 : 0) : 0)
    implicitHeight: Math.max(textLabel.implicitHeight, root.iconName ? root.iconSize : 0)
    Row {
      id: content
      anchors.centerIn: parent; spacing: 6
      width: Math.min(parent.width, parent.implicitWidth)
      Icon {
        visible: root.iconName !== ""; name: root.iconName; size: root.iconSize
        anchors.verticalCenter: parent.verticalCenter
        color: !root.enabled ? Theme.inactive : root.prominent ? root.accent : Theme.foreground
      }
      Text {
        id: textLabel
        width: Math.max(0, content.width - (root.iconName ? root.iconSize + (root.text ? content.spacing : 0) : 0))
        visible: root.text !== ""; text: root.text; font: root.font
        color: !root.enabled ? Theme.inactive : root.prominent ? root.accent : Theme.foreground
        elide: Text.ElideRight
      }
    }
  }
}
