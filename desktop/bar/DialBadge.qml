pragma ComponentBehavior: Bound
import QtQuick
import "../ui"
import "../ui/Theme.js" as Theme

// One small filled bubble for quota counters and the earbuds' audio check.
Rectangle {
  id: root
  property string text: ""
  property string iconName: ""
  property bool compact: false
  property real iconSize: Theme.barSize(compact ? 7 : 9)
  property string labelObjectName: "dialBadgeLabel"
  property color foreground: Theme.background
  implicitWidth: iconName !== "" ? implicitHeight
    : Math.max(implicitHeight, label.implicitWidth + Theme.barSize(compact ? 2 : 4))
  implicitHeight: Theme.barSize(compact ? 10 : 12)
  radius: height / 2
  color: Theme.usageAccent
  Accessible.role: Accessible.Indicator
  Text {
    id: label
    objectName: root.labelObjectName
    visible: root.iconName === ""
    anchors.centerIn: parent
    text: root.text
    color: root.foreground
    font.family: "Ubuntu"
    font.pixelSize: Theme.barSize(root.compact ? 7 : 9)
    font.bold: true
  }
  Icon {
    objectName: "dialBadgeIcon"
    visible: root.iconName !== ""
    anchors.centerIn: parent
    name: root.iconName
    size: root.iconSize
    color: root.foreground
  }
}
