import Quickshell.Hyprland
import QtQuick
import "../../ui/Theme.js" as Theme
import "../../ui"

Item {
  id: root

  property color backgroundColor: GlassState.enabled ? "transparent" : Theme.background
  property var monitor: null
  readonly property string monitorName: monitor?.name ?? ""
  property var workspaces: Hyprland.workspaces.values
  property var monitors: Hyprland.monitors.values
  readonly property int workspaceCount: 5
  // Match the compositor policy: a lone display always shows slots 1–5.
  readonly property bool internalMonitor: /^(eDP|LVDS|DSI)-/.test(monitorName)
  readonly property bool externalMonitorAvailable: monitors.some(output =>
    !/^(eDP|LVDS|DSI)-/.test(output.name)
    && (!output.lastIpcObject?.mirrorOf || output.lastIpcObject.mirrorOf === "none"))
  readonly property int firstWorkspaceId: internalMonitor && externalMonitorAvailable ? 6 : 1
  readonly property var workspaceIds: Array.from({length: workspaceCount},
    (_, index) => firstWorkspaceId + index)
  // workspacev2 can reach Quickshell before focusedmon and corrupt the old
  // monitor's activeWorkspace. Use the compositor snapshot, refreshed by
  // WorkspaceMonitorSync, rather than that focus-derived property.
  readonly property int activeWorkspaceId: monitor?.lastIpcObject?.activeWorkspace?.id ?? 0
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
  readonly property real specialSlotWidth: Math.max(workspaceButtonHeight,
    specialLabel.implicitWidth + Theme.barSize(12))
  readonly property real workspaceButtonHeight: Theme.barSize(24)
  readonly property real activeButtonWidth: Theme.barSize(40)
  readonly property real naturalContentWidth: {
    let total = 0;
    for (const workspaceId of workspaceIds) {
      total += workspaceId === activeWorkspaceId ? activeButtonWidth : workspaceButtonHeight;
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
    return workspaces.find(workspace => workspace.id === workspaceId) ?? null;
  }

  function focusWorkspace(workspaceId) {
    Hyprland.dispatch("hl.dsp.focus({ workspace = " + workspaceId + " })");
  }

  function toggleSpecialWorkspace(workspaceName) {
    Hyprland.dispatch("hl.dsp.workspace.toggle_special("
      + JSON.stringify(workspaceName) + ")");
  }

  function syncSpecialWorkspace(animate = true) {
    if (monitor === null || monitor.lastIpcObject === undefined)
      return;
    const special = monitor.lastIpcObject.specialWorkspace;
    setSpecialWorkspace(special !== undefined && special.id < 0
      ? special.name : "", animate);
  }

  readonly property real baseImplicitWidth: naturalContentWidth + Theme.barSize(12)
  // Workspace capsule geometry only; expanded panels choose their own width.
  readonly property real expandedImplicitWidth: baseImplicitWidth + specialSlotWidth
  implicitWidth: specialWorkspaceVisible ? expandedImplicitWidth : baseImplicitWidth
  implicitHeight: Theme.barSize(36)

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
    radius: Theme.barSize(18)
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
        spacing: (workspaceArea.width - root.naturalContentWidth - Theme.barSize(12))
          / Math.max(1, root.workspaceCount - 1)

      Repeater {
        model: root.workspaceIds

        Item {
          id: workspaceButton

          readonly property int workspaceId: modelData
          objectName: "workspace-" + workspaceId
          readonly property var workspace: root.workspaceForId(workspaceId)
          readonly property bool active: workspaceId === root.activeWorkspaceId
          readonly property bool occupied: workspace !== null
            && workspace.toplevels.values.length > 0
          readonly property bool hovered: pointer.containsMouse

          width: active ? root.activeButtonWidth : root.workspaceButtonHeight
          height: root.workspaceButtonHeight

          Behavior on width {
            NumberAnimation {
              duration: 400
              easing.type: Easing.OutCubic
            }
          }

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: workspaceButton.active ? Theme.action
              : workspaceButton.hovered ? Theme.surfaceRaised : "transparent"

            Behavior on color {
              ColorAnimation { duration: 220 }
            }

            // Keep the workspace characters, independently of the UI icon set.
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
              font.pixelSize: Theme.barSize(16)
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
          }

          MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.focusWorkspace(workspaceButton.workspaceId)
          }
        }
      }
    }
    }

    Rectangle {
      id: specialSlot
      objectName: "specialWorkspaceSlot"
      visible: root.specialSlotRendered
      opacity: root.specialSlotOpacity()
      anchors.right: parent.right
      anchors.rightMargin: Theme.barSize(6)
      anchors.verticalCenter: parent.verticalCenter
      width: root.specialSlotWidth
      height: root.workspaceButtonHeight
      radius: height / 2
      color: Theme.action

      Text {
        id: specialLabel
        objectName: "specialWorkspaceLabel"
        anchors.centerIn: parent
        text: root.specialSlotName
        color: Theme.background
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: Theme.barSize(13)
        font.bold: true
        font.weight: Font.Black
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: root.specialWorkspaceVisible
        onClicked: root.toggleSpecialWorkspace(root.specialSlotName)
      }
    }

  }
}
