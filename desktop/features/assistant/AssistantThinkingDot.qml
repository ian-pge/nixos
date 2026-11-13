import QtQuick
import QtQuick.Controls

// The thinking level beside the composer: green for the lowest level, red for
// the highest. A click steps to the next level, like Ctrl+Tab.
AbstractButton {
  id: root
  objectName: "assistantThinkingDot"
  property color color: "#a6da95"
  property string level: ""
  implicitWidth: 22; implicitHeight: 22
  focusPolicy: Qt.NoFocus
  hoverEnabled: true
  Accessible.name: "Thinking: " + level + " · Ctrl+Tab to change"
  ToolTip.visible: hovered; ToolTip.delay: 600
  ToolTip.text: "Thinking: " + level + " (Ctrl+Tab)"
  background: null
  contentItem: Item {
    Rectangle {
      anchors.centerIn: parent
      width: root.width * (root.hovered ? 1.1 : 1); height: width; radius: width / 2
      color: root.color
      antialiasing: true
      Behavior on color { ColorAnimation { duration: 160 } }
    }
  }
}
