import Quickshell
import QtQuick
import Local.LiquidGlass
import "./Theme.js" as Theme

Item {
  id: root

  property string text: ""
  property string iconName: ""
  property int textFormat: Text.AutoText
  property string trailingText: ""
  property bool trailingInactive: false
  property color accent: Theme.foreground
  property bool outlined: false
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

  implicitWidth: iconOnly ? Theme.barSize(36) : Math.max(Theme.barSize(36), content.implicitWidth + Theme.barSize(20))
  implicitHeight: Theme.barSize(36)

  function run(command) {
    if (command !== "")
      Quickshell.execDetached(["sh", "-c", command]);
  }

  Rectangle {
    objectName: "pill-background"
    id: glassBackground
    anchors.fill: parent
    radius: height / 2
    GlassShape { anchors.fill: parent; radius: glassBackground.radius; enabled: GlassState.enabled }
    color: GlassState.enabled
      ? Qt.alpha(Theme.background, 0.12) : Theme.background

    Behavior on color {
      ColorAnimation { duration: 220 }
    }
    Rectangle {
      objectName: "pill-selection"
      anchors.fill: parent
      anchors.margins: Theme.barSelectionInset()
      radius: height / 2
      color: root.hovered ? Qt.alpha(root.accent, Theme.barSelectionOpacity) : "transparent"
      Behavior on color { ColorAnimation { duration: 160 } }
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Theme.barSize(8)
      Icon {
        objectName: "pill-icon"
        visible: root.iconName !== ""; name: root.iconName; size: Theme.barIconSize
        anchors.verticalCenter: parent.verticalCenter
        color: root.accent
      }

      Text {
        id: label
        objectName: "pill-label"
        visible: root.text !== ""
        text: root.text
        textFormat: root.textFormat
        color: root.accent
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: Theme.barSize(16)
        font.bold: true

        Behavior on color { ColorAnimation { duration: 220 } }
      }

      Text {
        id: trailingLabel
        objectName: "pill-trailing-label"
        visible: root.trailingText !== ""
        text: root.trailingText
        color: root.trailingInactive ? Theme.inactive : root.accent
        font: label.font

        Behavior on color { ColorAnimation { duration: 220 } }
      }
    }
  }

  Rectangle {
    objectName: "pill-outline"
    anchors.fill: parent
    anchors.margins: Theme.barOutlineInset()
    visible: root.outlined
    radius: height / 2
    color: "transparent"
    border.width: Theme.barOutlineWidth
    border.color: root.accent
  }

  // The full capsule remains clickable, including the selection's outer margin.
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
