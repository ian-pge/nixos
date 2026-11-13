import QtQuick
import Quickshell
import Quickshell.Hyprland

// Session-wide presentation of the Qwen notch: where and when it is open.
// AssistantData owns the conversation; closing never cancels a reply.
Scope {
  id: root
  required property var assistantData
  property bool blocked: false
  property bool visible: false
  property bool passive: false
  property string targetMonitor: ""
  property int focusSerial: 0
  property string focusedMonitor: Hyprland.focusedMonitor?.name || availableMonitors[0] || ""
  property var monitors: Hyprland.monitors.values
  property var availableMonitors: monitors.map(monitor => monitor.name)
  readonly property var targetMonitorState: monitors.find(monitor => monitor.name === targetMonitor)?.lastIpcObject
  // WorkspaceMonitorSync refreshes this snapshot after compositor events.
  readonly property int targetWorkspaceId: targetMonitorState?.activeWorkspace?.id ?? 0
  readonly property int targetSpecialWorkspaceId: targetMonitorState?.specialWorkspace?.id ?? 0

  function show(monitor = "") {
    if (blocked) return;
    assistantData.dismissCorrection();
    passive = false;
    targetMonitor = monitor || focusedMonitor;
    visible = true;
    ++focusSerial;
  }
  function hide() { visible = false; assistantData.dismissCorrection(); }
  function toggle(monitor = "") {
    const target = monitor || focusedMonitor;
    if (visible && targetMonitor === target) hide();
    else show(target);
  }
  onAvailableMonitorsChanged: if (visible && !availableMonitors.includes(targetMonitor)) hide()
  onFocusedMonitorChanged: if (visible && focusedMonitor && focusedMonitor !== targetMonitor) hide()
  onTargetWorkspaceIdChanged: if (visible) hide()
  onTargetSpecialWorkspaceIdChanged: if (visible) hide()
  Connections {
    target: root.assistantData
    function onCorrectionClosed() { root.hide(); }
    function onCorrectionPresented() {
      if (root.blocked) return;
      if (!root.visible) { root.passive = true; root.targetMonitor = root.focusedMonitor; root.visible = true; }
    }
  }
}
