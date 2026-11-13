import QtQuick
import QtQuick.Controls
import "../../ui/Theme.js" as Theme

// The model logo of an empty conversation. Tab or a click switches model;
// the logo changes at once, without animation.
Button {
  id: root
  objectName: "assistantModelSwitch"
  required property var model
  property real size: 44
  implicitWidth: size; implicitHeight: size
  padding: 0
  focusPolicy: Qt.NoFocus
  Accessible.name: "Model: " + (model?.title || "") + " · Tab to switch"
  ToolTip.visible: hovered; ToolTip.delay: 600
  ToolTip.text: "Switch model (Tab)"
  background: Rectangle {
    radius: width / 2
    color: Qt.alpha(root.model?.accent || Theme.flamingo, root.hovered ? 0.3 : 0.18)
  }
  contentItem: Item {
    Rectangle {
      objectName: "assistantModelLogo"
      anchors.centerIn: parent
      width: Math.round(root.size * 0.78); height: width; radius: width / 2
      color: "#ffffff"
      antialiasing: true
      Image {
        anchors { fill: parent; margins: parent.width * 0.18 }
        source: root.model?.logo || ""
        sourceSize: Qt.size(parent.width * 2, parent.width * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
      }
    }
  }
}
