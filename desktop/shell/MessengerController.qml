import QtQuick
import Quickshell
import Quickshell.Hyprland

// Session-wide presentation state only. The messenger model owns API/drafts;
// this shell controller owns where and when the independent panel is shown.
Scope {
  id: root
  required property var beeperData
  property bool blocked: false
  property bool visible: false
  property string targetMonitor: ""
  property int focusSerial: 0
  signal aboutToShow()
  property string focusedMonitor: Hyprland.focusedMonitor?.name || availableMonitors[0] || ""
  property var monitors: Hyprland.monitors.values
  property var availableMonitors: monitors.map(monitor => monitor.name)
  readonly property var targetMonitorState: monitors.find(monitor => monitor.name === targetMonitor)?.lastIpcObject
  // WorkspaceMonitorSync refreshes this snapshot after compositor events.
  // activeWorkspace itself can briefly belong to the wrong monitor during a switch.
  readonly property int targetWorkspaceId: targetMonitorState?.activeWorkspace?.id ?? 0
  readonly property int targetSpecialWorkspaceId: targetMonitorState?.specialWorkspace?.id ?? 0

  function show(monitor = "") {
    if (blocked) return;
    targetMonitor = monitor || focusedMonitor;
    aboutToShow();
    visible = true;
    ++focusSerial;
  }
  function hide() {
    visible = false;
  }
  function toggle(monitor = "") {
    const target = monitor || focusedMonitor;
    if (visible && targetMonitor === target) hide();
    else show(target);
  }
  onAvailableMonitorsChanged: {
    if (visible && !availableMonitors.includes(targetMonitor)) hide();
  }
  onFocusedMonitorChanged: {
    if (visible && focusedMonitor && focusedMonitor !== targetMonitor) hide();
  }
  onTargetWorkspaceIdChanged: { if (visible) hide(); }
  onTargetSpecialWorkspaceIdChanged: { if (visible) hide(); }
  Connections {
    target: root.beeperData
    function onOpenRequested(chatID, messageID) {
      root.show();
      root.beeperData.selectChat(chatID, messageID);
    }
  }
}
