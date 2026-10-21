import Quickshell.Hyprland
import QtQuick
import "../../ui/Theme.js" as Theme
import "../../ui/Morph.js" as Morph
import "../../ui"

Item {
  id: root

  property color backgroundColor: GlassState.enabled ? "transparent" : Theme.background
  property var monitor: null
  readonly property string monitorName: monitor?.name ?? ""
  property var workspaces: Hyprland.workspaces.values
  property var monitors: Hyprland.monitors.values
  // Match the compositor policy: the laptop alone keeps all ten workspaces.
  readonly property bool internalMonitor: /^(eDP|LVDS|DSI)-/.test(monitorName)
  readonly property bool externalMonitorAvailable: monitors.some(output =>
    !/^(eDP|LVDS|DSI)-/.test(output.name)
    && (!output.lastIpcObject?.mirrorOf || output.lastIpcObject.mirrorOf === "none"))
  readonly property int workspaceCount: internalMonitor && !externalMonitorAvailable ? 10 : 5
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
  property real specialTransitionStartWidth: 0
  readonly property bool specialWorkspaceVisible: activeSpecialWorkspace !== ""
  readonly property bool specialSlotRendered: presentedSpecialWorkspace !== ""
  readonly property string specialSlotName: presentedSpecialWorkspace.startsWith("special:")
    ? presentedSpecialWorkspace.slice(8) : presentedSpecialWorkspace
  readonly property real specialSlotWidth: Math.max(workspaceButtonHeight,
    specialLabel.implicitWidth + Theme.barSize(12))
  readonly property real presentedSpecialWidth: specialTransitionStartWidth
    + ((specialTransitionTargetVisible ? specialSlotWidth : 0) - specialTransitionStartWidth)
      * Morph.easeOut(specialTransitionProgress)
  // Share the visible ring inset, not the larger hit area's inset. The pink
  // capsule and inactive hover circles then match the neighbouring dials.
  readonly property real contentInset: Theme.barOutlineInset()
  readonly property real workspaceButtonHeight: implicitHeight - 2 * contentInset
  readonly property real inactiveButtonWidth: workspaceButtonHeight
  readonly property real activeButtonWidth: workspaceButtonHeight + Theme.barSize(32)
  readonly property real naturalContentWidth: {
    let total = 0;
    for (const workspaceId of workspaceIds) {
      total += workspaceId === activeWorkspaceId ? activeButtonWidth : inactiveButtonWidth;
    }
    return total;
  }

  function specialSlotOpacity() {
    return specialTransitionTargetVisible
      ? Morph.incoming(specialTransitionStartOpacity, specialTransitionProgress)
      : Morph.outgoing(specialTransitionStartOpacity, specialTransitionProgress);
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

    const currentOpacity = specialSlotOpacity();
    const currentWidth = presentedSpecialWidth;
    specialTransition.stop();
    activeSpecialWorkspace = workspaceName;
    if (targetVisible)
      presentedSpecialWorkspace = workspaceName;
    specialTransitionTargetVisible = targetVisible;
    specialTransitionStartOpacity = currentOpacity;
    specialTransitionStartWidth = currentWidth;
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

  readonly property real baseImplicitWidth: naturalContentWidth + 2 * contentInset
  // Workspace capsule geometry only; expanded panels choose their own width.
  readonly property real expandedImplicitWidth: baseImplicitWidth + specialSlotWidth
  // The outer capsule needs the destination immediately, but its visible row
  // must keep its current layout until the new slot has grown into place.
  readonly property real presentedImplicitWidth: baseImplicitWidth + presentedSpecialWidth
  implicitWidth: specialWorkspaceVisible ? expandedImplicitWidth : baseImplicitWidth
  implicitHeight: Theme.barWorkspaceHeight

  Component.onCompleted: Qt.callLater(() => syncSpecialWorkspace(false))

  Timer {
    interval: 200
    running: true
    onTriggered: root.syncSpecialWorkspace(false)
  }

  NumberAnimation {
    id: specialTransition
    objectName: "specialWorkspaceTransition"
    target: root
    property: "specialTransitionProgress"
    from: 0
    to: 1
    duration: Morph.duration
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
    radius: height / 2
    color: root.backgroundColor

    Item {
      id: workspaceArea
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.min(root.baseImplicitWidth, parent.width)

      Row {
        id: workspaceRow
        // Keep fractional-sized circles centered without anchor rounding offsets.
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        spacing: Math.max(0, (workspaceArea.width - root.naturalContentWidth - 2 * root.contentInset)
          / Math.max(1, root.workspaceCount - 1))

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

          width: active ? root.activeButtonWidth : root.inactiveButtonWidth
          height: root.workspaceButtonHeight

          Behavior on width {
            NumberAnimation {
              duration: 400
              easing.type: Easing.OutCubic
            }
          }

          Rectangle {
            objectName: "workspaceHighlight"
            anchors.fill: parent
            radius: height / 2
            color: workspaceButton.active ? Theme.action
              : workspaceButton.hovered ? Theme.surfaceRaised : "transparent"

            Behavior on color {
              ColorAnimation { duration: 220 }
            }

            // Keep the workspace characters, independently of the UI icon set.
            Text {
              objectName: "workspaceGlyph"
              // Keep the glyph centered at fractional sizes, including the
              // final frame, without rounded center-anchor offsets.
              x: (parent.width - width) / 2
              y: (parent.height - height) / 2
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

    Item {
      id: specialReveal
      objectName: "specialWorkspaceReveal"
      visible: root.specialSlotRendered
      // Reveal only the added space, never paint over an existing workspace.
      x: root.baseImplicitWidth - root.contentInset
      y: (parent.height - height) / 2
      width: root.presentedSpecialWidth
      height: root.workspaceButtonHeight
      clip: true

      Rectangle {
        id: specialSlot
        objectName: "specialWorkspaceSlot"
        opacity: root.specialSlotOpacity()
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: root.specialSlotWidth
        height: root.workspaceButtonHeight
        radius: height / 2
        color: Theme.action
        transform: MorphScale { surface: specialReveal; content: specialSlot }

        Text {
          id: specialLabel
          objectName: "specialWorkspaceLabel"
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
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
}
