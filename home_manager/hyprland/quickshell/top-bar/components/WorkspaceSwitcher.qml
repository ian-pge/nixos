import Quickshell.Hyprland
import QtQuick

Item {
  id: root

  property color backgroundColor: "#181926"
  property string monitorName: ""
  property string activeSpecialWorkspace: ""
  readonly property bool specialWorkspaceVisible: activeSpecialWorkspace !== ""
  readonly property string specialWorkspaceName: activeSpecialWorkspace.startsWith("special:")
    ? activeSpecialWorkspace.slice(8) : activeSpecialWorkspace
  readonly property real specialSlotWidth: Math.max(70, specialLabel.implicitWidth + 24)
  readonly property real specialExtraWidth: specialWorkspaceVisible
    ? specialSlotWidth + 12 : 0
  readonly property real naturalContentWidth: {
    let total = 0;
    for (let workspaceId = 1; workspaceId <= 8; workspaceId++) {
      const workspace = workspaceForId(workspaceId);
      total += workspace !== null && workspace.focused ? 60 : 40;
    }
    return total;
  }

  function workspaceForId(workspaceId) {
    return Hyprland.workspaces.values.find(workspace => workspace.id === workspaceId) ?? null;
  }

  function syncSpecialWorkspace() {
    const monitor = Hyprland.monitors.values.find(candidate =>
      candidate.name === monitorName);
    if (monitor === undefined || monitor.lastIpcObject === undefined)
      return;
    const special = monitor.lastIpcObject.specialWorkspace;
    activeSpecialWorkspace = special !== undefined && special.id < 0
      ? special.name : "";
  }

  readonly property real baseImplicitWidth: naturalContentWidth + 12
  implicitWidth: baseImplicitWidth + specialExtraWidth
  implicitHeight: 36

  Component.onCompleted: Qt.callLater(syncSpecialWorkspace)

  Timer {
    interval: 200
    running: true
    onTriggered: root.syncSpecialWorkspace()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event.name !== "activespecial")
        return;
      const separator = event.data.lastIndexOf(",");
      if (separator < 0 || event.data.slice(separator + 1) !== root.monitorName)
        return;
      root.activeSpecialWorkspace = event.data.slice(0, separator);
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: 18
    color: root.backgroundColor

    Item {
      id: workspaceArea
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.max(12, parent.width - root.specialExtraWidth)

      Row {
        id: workspaceRow
        anchors.centerIn: parent
        spacing: (workspaceArea.width - root.naturalContentWidth - 12) / 7

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
                duration: 180
                easing.type: Easing.OutCubic
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
    }

    Rectangle {
      id: specialSlot
      visible: root.specialWorkspaceVisible
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: root.specialSlotWidth
      height: 24
      radius: 12
      color: "#ff33cc"

      Text {
        id: specialLabel
        anchors.centerIn: parent
        text: root.specialWorkspaceName
        color: "#181926"
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 13
        font.bold: true
        font.weight: Font.Black
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Hyprland.dispatch("togglespecialworkspace "
          + root.specialWorkspaceName)
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
