import Quickshell.Hyprland
import QtQuick

Item {
  id: root

  property color backgroundColor: "#181926"

  function workspaceForId(workspaceId) {
    return Hyprland.workspaces.values.find(workspace => workspace.id === workspaceId) ?? null;
  }

  implicitWidth: workspaceRow.implicitWidth + 12
  implicitHeight: 36

  Behavior on implicitWidth {
    NumberAnimation {
      duration: 400
      easing.type: Easing.OutCubic
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: 18
    color: root.backgroundColor

    Row {
      id: workspaceRow
      anchors.centerIn: parent
      spacing: 0

      Repeater {
        model: 8

        Rectangle {
          id: workspaceButton

          readonly property int workspaceId: index + 1
          readonly property var workspace: root.workspaceForId(workspaceId)
          readonly property bool active: workspace !== null && workspace.focused
          readonly property bool occupied: workspace !== null
            && workspace.toplevels.values.length > 0
          readonly property bool hovered: pointer.containsMouse

          width: active ? 60 : 40
          height: 24
          radius: 16
          color: active
            ? "#ff33cc"
            : hovered ? "#363a4f" : "transparent"

          Behavior on width {
            NumberAnimation {
              duration: 400
              easing.type: Easing.OutCubic
            }
          }

          Behavior on color {
            ColorAnimation { duration: 220 }
          }

          Text {
            anchors.centerIn: parent
            text: workspaceButton.active
              ? "󰮯"
              : workspaceButton.occupied ? "󰊠" : ""
            color: workspaceButton.active
              ? "#181926"
              : workspaceButton.hovered
                ? "#ff33cc"
                : workspaceButton.occupied ? "#ffcc33" : "#6e738d"
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 16
            font.bold: true
            scale: workspaceButton.hovered && !workspaceButton.active ? 1.14 : 1

            Behavior on color {
              ColorAnimation { duration: 220 }
            }

            Behavior on scale {
              NumberAnimation {
                duration: 220
                easing.type: Easing.OutBack
              }
            }
          }

          MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Hyprland.dispatch("workspace " + workspaceButton.workspaceId)
          }
        }
      }
    }

    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: event => {
        if (event.angleDelta.y < 0)
          Hyprland.dispatch("workspace r+1");
        else if (event.angleDelta.y > 0)
          Hyprland.dispatch("workspace r-1");
      }
    }
  }
}
