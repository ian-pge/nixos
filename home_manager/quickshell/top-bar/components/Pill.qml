import Quickshell
import QtQuick
import "Theme.js" as Theme

Item {
  id: root

  property string text: ""
  property string trailingText: ""
  property bool trailingInactive: false
  property color accent: Theme.foreground
  property string leftCommand: ""
  property string rightCommand: ""
  property string wheelUpCommand: ""
  property string wheelDownCommand: ""
  property bool iconOnly: false
  property bool interactive: leftCommand !== "" || rightCommand !== ""
    || wheelUpCommand !== "" || wheelDownCommand !== ""
  property bool forceHovered: false
  readonly property bool hovered: forceHovered || pointer.containsMouse

  signal leftClicked()
  signal rightClicked()
  signal wheelUp()
  signal wheelDown()

  implicitWidth: iconOnly ? 36 : Math.max(36, label.implicitWidth + 20
    + (trailingText !== "" ? trailingLabel.implicitWidth + 8 : 0))
  implicitHeight: 36

  function run(command) {
    if (command !== "")
      Quickshell.execDetached(["sh", "-c", command]);
  }

  Rectangle {
    anchors.fill: parent
    radius: 18
    color: root.hovered ? root.accent : Theme.background
    transform: SelectionBounce {
      active: root.hovered && root.visible && root.enabled
    }

    Behavior on color {
      ColorAnimation { duration: 220 }
    }

    Row {
      anchors.centerIn: parent
      spacing: 8

      Text {
        id: label
        text: root.text
        color: root.hovered ? Theme.background : root.accent
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 16
        font.bold: true

        Behavior on color { ColorAnimation { duration: 220 } }
      }

      Text {
        id: trailingLabel
        visible: root.trailingText !== ""
        text: root.trailingText
        color: root.trailingInactive ? Theme.inactive
          : root.hovered ? Theme.background : root.accent
        font: label.font

        Behavior on color { ColorAnimation { duration: 220 } }
      }
    }
  }

  // Keep the hit area still so the bounce cannot toggle hover at its edges.
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

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
