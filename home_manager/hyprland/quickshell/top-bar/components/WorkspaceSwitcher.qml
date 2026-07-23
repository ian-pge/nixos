import Quickshell.Hyprland
import QtQuick
import "Theme.js" as Theme

Item {
  id: root

  property color backgroundColor: Theme.background
  property string monitorName: ""
  property string activeSpecialWorkspace: ""
  property string presentedSpecialWorkspace: ""
  property bool specialTransitionTargetVisible: false
  property bool specialWorkspaceInitialized: false
  property real specialTransitionProgress: 1
  property real specialTransitionStartOpacity: 0
  readonly property bool specialWorkspaceVisible: activeSpecialWorkspace !== ""
  readonly property bool specialSlotRendered: presentedSpecialWorkspace !== ""
  readonly property string specialSlotName: presentedSpecialWorkspace.startsWith("special:")
    ? presentedSpecialWorkspace.slice(8) : presentedSpecialWorkspace
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

  function clamp01(value) {
    return Math.max(0, Math.min(1, value));
  }

  function smoothSegment(start, end, value) {
    const progress = clamp01((value - start) / (end - start));
    return progress * progress * (3 - 2 * progress);
  }

  function specialSlotOpacity() {
    if (specialTransitionTargetVisible) {
      const entryProgress = smoothSegment(0.18, 0.78,
        specialTransitionProgress);
      return specialTransitionStartOpacity
        + (1 - specialTransitionStartOpacity) * entryProgress;
    }
    return specialTransitionStartOpacity
      * (1 - smoothSegment(0, 0.48, specialTransitionProgress));
  }

  function setSpecialWorkspace(workspaceName, animate = true) {
    if (specialWorkspaceInitialized
        && workspaceName === activeSpecialWorkspace)
      return;

    const targetVisible = workspaceName !== "";
    if (!specialWorkspaceInitialized || !animate) {
      specialTransition.stop();
      activeSpecialWorkspace = workspaceName;
      presentedSpecialWorkspace = workspaceName;
      specialTransitionTargetVisible = targetVisible;
      specialTransitionStartOpacity = targetVisible ? 1 : 0;
      specialTransitionProgress = 1;
      specialWorkspaceInitialized = true;
      return;
    }

    if (targetVisible && specialTransitionTargetVisible
        && activeSpecialWorkspace !== "") {
      activeSpecialWorkspace = workspaceName;
      presentedSpecialWorkspace = workspaceName;
      return;
    }

    const currentOpacity = specialSlotOpacity();
    specialTransition.stop();
    activeSpecialWorkspace = workspaceName;
    if (targetVisible)
      presentedSpecialWorkspace = workspaceName;
    specialTransitionTargetVisible = targetVisible;
    specialTransitionStartOpacity = currentOpacity;
    specialTransitionProgress = 0;
    specialTransition.restart();
  }

  function workspaceForId(workspaceId) {
    return Hyprland.workspaces.values.find(workspace => workspace.id === workspaceId) ?? null;
  }

  function syncSpecialWorkspace(animate = true) {
    const monitor = Hyprland.monitors.values.find(candidate =>
      candidate.name === monitorName);
    if (monitor === undefined || monitor.lastIpcObject === undefined)
      return;
    const special = monitor.lastIpcObject.specialWorkspace;
    setSpecialWorkspace(special !== undefined && special.id < 0
      ? special.name : "", animate);
  }

  readonly property real baseImplicitWidth: naturalContentWidth + 12
  implicitWidth: baseImplicitWidth + specialExtraWidth
  implicitHeight: 36

  Component.onCompleted: Qt.callLater(() => syncSpecialWorkspace(false))

  Timer {
    interval: 200
    running: true
    onTriggered: root.syncSpecialWorkspace(false)
  }

  NumberAnimation {
    id: specialTransition
    target: root
    property: "specialTransitionProgress"
    from: 0
    to: 1
    duration: 360
    easing.type: Easing.Linear
    onFinished: {
      if (!root.specialTransitionTargetVisible)
        root.presentedSpecialWorkspace = "";
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event.name !== "activespecial")
        return;
      const separator = event.data.lastIndexOf(",");
      if (separator < 0 || event.data.slice(separator + 1) !== root.monitorName)
        return;
      root.setSpecialWorkspace(event.data.slice(0, separator));
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
      width: Math.min(root.baseImplicitWidth, parent.width)

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
            ? Theme.action
            : hovered ? Theme.surfaceRaised : "transparent"

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
              ? Theme.background
              : workspaceButton.hovered
                ? Theme.action
                : workspaceButton.occupied ? Theme.state : Theme.inactive
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
      visible: root.specialSlotRendered
      opacity: root.specialSlotOpacity()
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      width: root.specialSlotWidth
      height: 24
      radius: 12
      color: Theme.action

      Text {
        id: specialLabel
        anchors.centerIn: parent
        text: root.specialSlotName
        color: Theme.background
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 13
        font.bold: true
        font.weight: Font.Black
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.specialWorkspaceVisible
        onClicked: Hyprland.dispatch("togglespecialworkspace "
          + root.specialSlotName)
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
