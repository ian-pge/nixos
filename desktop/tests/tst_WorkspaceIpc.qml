import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtTest

// Run only through workspaces_test.mjs: every IPC request goes to its fake
// compositor, never to the user's Hyprland session.
ShellRoot {
  id: root
  property var first: null
  property var second: null
  property var synchronizer: null
  property bool observedOldMonitorBug: false
  property bool wrongSourceIndicator: false
  property bool watchingCrossMonitorSwitch: false

  function monitor(name) {
    return Hyprland.monitors.values.find(item => item.name === name) ?? null;
  }

  Component.onCompleted: {
    if (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== "quickshell-workspace-test"
        || Quickshell.env("QUICKSHELL_WORKSPACE_TEST") !== "1") {
      console.error("Use workspaces_test.mjs to isolate this test from the desktop");
      Qt.exit(1);
      return;
    }
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/workspaces/WorkspaceMonitorSync.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString());
      Qt.exit(1);
      return;
    }
    synchronizer = component.createObject(root);
  }

  Window { id: testWindow; visible: true; width: 550; height: 130 }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.watchingCrossMonitorSwitch && event.name === "workspacev2"
          && root.monitor("DP-2")?.activeWorkspace?.id === 6)
        root.observedOldMonitorBug = true;
    }
  }
  Connections {
    target: root.first
    function onActiveWorkspaceIdChanged() {
      if (root.watchingCrossMonitorSwitch && root.first.activeWorkspaceId !== 3)
        root.wrongSourceIndicator = true;
    }
  }

  TestResult { id: results }
  TestCase {
    name: "WorkspaceIpc"
    when: root.synchronizer !== null && root.monitor("DP-2") !== null
      && root.monitor("eDP-1") !== null

    function cleanupTestCase() {
      console.log("WorkspaceIpc: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount > 0 ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function initTestCase() {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/workspaces/WorkspaceSwitcher.qml");
      compare(component.status, Component.Ready, component.errorString());
      root.first = component.createObject(testWindow.contentItem, {monitor: root.monitor("DP-2"), y: 10});
      root.second = component.createObject(testWindow.contentItem, {monitor: root.monitor("eDP-1"), y: 60});
      verify(root.first !== null && root.second !== null);
      tryCompare(root.first, "activeWorkspaceId", 3);
      tryCompare(root.second, "activeWorkspaceId", 5);
    }
    function verifyPair(firstId, secondId) {
      console.log("Checking monitor workspaces", firstId, secondId);
      tryCompare(root.first, "activeWorkspaceId", firstId);
      tryCompare(root.second, "activeWorkspaceId", secondId);
      for (const widget of [root.first, root.second]) {
        compare(widget.expandedImplicitWidth, 434);
        for (let id = 1; id <= 8; id++)
          compare(findChild(widget, "workspace-" + id).active, widget.activeWorkspaceId === id);
      }
    }
    function test_event_sequence() {
      root.watchingCrossMonitorSwitch = true;
      // Exercise the real click dispatcher and real Quickshell C++ event
      // processing against the fake compositor, including workspacev2 first.
      root.first.focusWorkspace(6);
      verifyPair(3, 6);
      console.log("Cross-monitor regression observed:", root.observedOldMonitorBug,
        "wrong indicator:", root.wrongSourceIndicator);
      verify(root.observedOldMonitorBug, "Fixture must reproduce the native model corruption");
      verify(!root.wrongSourceIndicator, "Dell must never highlight the other monitor's workspace");
      root.watchingCrossMonitorSwitch = false;

      root.second.focusWorkspace(7);
      verifyPair(3, 7);
      // Going back to an already visible workspace only changes monitor focus.
      root.second.focusWorkspace(3);
      tryVerify(() => Hyprland.focusedMonitor?.name === "DP-2");
      verifyPair(3, 7);
      root.first.focusWorkspace(2);
      verifyPair(2, 7);
      // Reverse direction: eDP-1 is now the source and must keep 7.
      root.second.focusWorkspace(5);
      verifyPair(2, 5);
      root.second.focusWorkspace(4);
      verifyPair(4, 5);
    }
  }
}
