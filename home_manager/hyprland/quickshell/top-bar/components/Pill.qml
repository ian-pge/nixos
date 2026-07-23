import Quickshell
import QtQuick
import "Theme.js" as Theme

Rectangle {
  id: root

  property string text: ""
  property color accent: Theme.foreground
  property string tooltipText: ""
  property var tooltipHost: null
  property string leftCommand: ""
  property string rightCommand: ""
  property string wheelUpCommand: ""
  property string wheelDownCommand: ""
  property bool interactive: leftCommand !== "" || rightCommand !== ""
    || wheelUpCommand !== "" || wheelDownCommand !== ""

  signal leftClicked()
  signal rightClicked()
  signal wheelUp()
  signal wheelDown()

  implicitWidth: label.implicitWidth + 20
  implicitHeight: 36
  radius: 18
  color: pointer.containsMouse ? accent : Theme.background

  function run(command) {
    if (command !== "")
      Quickshell.execDetached(["sh", "-c", command]);
  }

  Behavior on color {
    ColorAnimation { duration: 220 }
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    color: pointer.containsMouse ? Theme.background : root.accent
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 16
    font.bold: true

    Behavior on color {
      ColorAnimation { duration: 220 }
    }
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

    onEntered: {
      if (root.tooltipHost !== null && root.tooltipText !== "")
        root.tooltipHost.showTooltip(root, root.tooltipText);
    }

    onExited: {
      if (root.tooltipHost !== null)
        root.tooltipHost.hideTooltip(root);
    }

    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) {
        root.run(root.rightCommand);
        root.rightClicked();
      } else {
        root.run(root.leftCommand);
        root.leftClicked();
      }
    }

    onWheel: wheel => {
      if (wheel.angleDelta.y > 0) {
        root.run(root.wheelUpCommand);
        root.wheelUp();
      } else if (wheel.angleDelta.y < 0) {
        root.run(root.wheelDownCommand);
        root.wheelDown();
      }
    }
  }
}
