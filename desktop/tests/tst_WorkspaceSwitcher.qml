import Quickshell
import QtQuick
import QtTest

ShellRoot {
  id: root
  property var first: null
  property var second: null

  QtObject {
    id: workspaceOne
    property int id: 1
    property bool focused: true
    property var toplevels: ({values: [{}]})
  }
  QtObject {
    id: workspaceTwo
    property int id: 2
    property bool focused: false
    property var toplevels: ({values: []})
  }
  QtObject {
    id: workspaceThree
    property int id: 3
    property bool focused: false
    property var toplevels: ({values: [{}]})
  }
  QtObject {
    id: workspaceSix
    property int id: 6
    property bool focused: false
    property var toplevels: ({values: [{}]})
  }
  QtObject {
    id: workspaceSeven
    property int id: 7
    property bool focused: false
    property var toplevels: ({values: []})
  }
  QtObject {
    id: firstMonitor
    property string name: "DP-2"
    property bool focused: true
    property var activeWorkspace: workspaceOne
    property var lastIpcObject: ({activeWorkspace: {id: 1}, specialWorkspace: {id: 0, name: ""}})
  }
  QtObject {
    id: secondMonitor
    property string name: "eDP-1"
    property bool focused: false
    property var activeWorkspace: workspaceSix
    property var lastIpcObject: ({activeWorkspace: {id: 6}, specialWorkspace: {id: 0, name: ""}})
  }
  Window {
    id: testWindow
    visible: true
    width: 550
    height: 130
  }
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/workspaces/WorkspaceSwitcher.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString());
      Qt.exit(1);
      return;
    }
    const properties = {
      x: 10, y: 10,
      workspaces: [workspaceOne, workspaceTwo, workspaceThree, workspaceSix, workspaceSeven],
      monitor: firstMonitor,
      monitors: [firstMonitor, secondMonitor]
    };
    first = component.createObject(testWindow.contentItem, properties);
    properties.y = 60;
    properties.monitor = secondMonitor;
    second = component.createObject(testWindow.contentItem, properties);
  }

  TestResult { id: results }
  TestCase {
    name: "WorkspaceSwitcher"
    when: root.first !== null && root.second !== null && testWindow.visible

    function cleanupTestCase() {
      console.log("WorkspaceSwitcher: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount > 0 ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function init() {
      workspaceOne.focused = true;
      workspaceTwo.focused = false;
      workspaceThree.focused = false;
      workspaceSix.focused = false;
      firstMonitor.focused = true;
      secondMonitor.focused = false;
      setWorkspace(firstMonitor, workspaceOne);
      firstMonitor.name = "DP-2";
      secondMonitor.name = "eDP-1";
      setWorkspace(secondMonitor, workspaceSix);
      for (const widget of [root.first, root.second]) {
        widget.monitors = [firstMonitor, secondMonitor];
        widget.workspaces = [workspaceOne, workspaceTwo, workspaceThree, workspaceSix, workspaceSeven];
        widget.setSpecialWorkspace("", false);
      }
      root.first.monitor = firstMonitor;
      root.second.monitor = secondMonitor;
      mouseMove(testWindow.contentItem, 520, 110);
      wait(450);
    }
    function button(widget, id) { return findChild(widget, "workspace-" + id); }
    function label(widget, id) { return button(widget, id).children[0].children[0]; }
    function setWorkspace(monitor, workspace) {
      monitor.activeWorkspace = workspace;
      monitor.lastIpcObject = {
        activeWorkspace: workspace === null ? null : {id: workspace.id},
        specialWorkspace: {id: 0, name: ""}
      };
    }
    function verifyActive(widget, activeId) {
      compare(widget.activeWorkspaceId, activeId);
      compare(widget.workspaceIds.length, 5);
      for (let id = 1; id <= 10; id++) {
        const item = button(widget, id);
        if (!widget.workspaceIds.includes(id)) {
          verify(item === null, "Other monitor's slots must not appear");
          continue;
        }
        verify(item !== null, "Every monitor must keep its five slots");
        compare(item.active, id === activeId);
        tryCompare(item, "width", id === activeId ? 70 : 47);
      }
    }
    function test_each_monitor_has_its_own_pacman() {
      verifyActive(root.first, 1);
      verifyActive(root.second, 6);
      compare(root.first.workspaceIds.join(","), "1,2,3,4,5");
      compare(root.second.workspaceIds.join(","), "6,7,8,9,10");
      compare(label(root.first, 1).text, "󰮯");
      compare(label(root.second, 6).text, "󰮯");
      compare(button(root.first, 1).children[0].color, "#ff33cc");
      compare(button(root.second, 6).children[0].color, "#ff33cc");
      compare(label(root.first, 3).text, "󰊠");
      compare(label(root.first, 3).color, "#ffcc33");
      compare(label(root.second, 7).text, "");
      compare(label(root.second, 7).color, "#6e738d");
      compare(label(root.first, 2).text, "");
      compare(label(root.first, 2).color, "#6e738d");
    }
    function test_global_focus_does_not_change_local_selection_or_width() {
      workspaceOne.focused = false;
      workspaceSix.focused = true;
      firstMonitor.focused = false;
      secondMonitor.focused = true;
      verifyActive(root.first, 1);
      verifyActive(root.second, 6);
      // Focusing a special workspace can leave all normal workspaces unfocused.
      workspaceSix.focused = false;
      for (const widget of [root.first, root.second]) {
        compare(widget.naturalContentWidth, 258);
        compare(widget.baseImplicitWidth, 272);
        compare(widget.expandedImplicitWidth, 368);
      }
      verifyActive(root.first, 1);
      verifyActive(root.second, 6);
    }
    function test_changing_one_workspace_does_not_change_the_other_bar() {
      setWorkspace(secondMonitor, workspaceSeven);
      verifyActive(root.first, 1);
      verifyActive(root.second, 7);
      compare(label(root.second, 7).text, "󰮯");
      compare(label(root.second, 6).text, "󰊠");
      compare(root.second.expandedImplicitWidth, 368);
    }
    function test_cross_monitor_switch_keeps_the_source_workspace() {
      setWorkspace(firstMonitor, workspaceThree);
      setWorkspace(secondMonitor, workspaceSix);
      // Quickshell 0.3.1 handles workspacev2 before focusedmon: it assigns 7
      // to the old focused monitor even though Hyprland still displays 3.
      firstMonitor.activeWorkspace = {id: 7};
      verifyActive(root.first, 3);
      verifyActive(root.second, 6);
      firstMonitor.focused = false;
      secondMonitor.focused = true;
      secondMonitor.activeWorkspace = {id: 7};
      verifyActive(root.first, 3);
      // Only the authoritative reply advances the destination indicator.
      secondMonitor.lastIpcObject = {
        activeWorkspace: {id: 7}, specialWorkspace: {id: 0, name: ""}
      };
      verifyActive(root.first, 3);
      verifyActive(root.second, 7);
      compare(root.first.expandedImplicitWidth, 368);
      compare(root.second.expandedImplicitWidth, 368);
    }
    function test_monitor_can_disconnect_or_be_reassigned() {
      root.first.monitor = null;
      verifyActive(root.first, 0);
      compare(root.first.monitorName, "");
      verifyActive(root.second, 6);
      compare(root.first.naturalContentWidth, 235);
      root.first.monitor = firstMonitor;
      verifyActive(root.first, 1);
      compare(root.first.monitorName, "DP-2");
      root.first.monitor = secondMonitor;
      verifyActive(root.first, 6);
      compare(root.first.monitorName, "eDP-1");
      compare(root.first.workspaceIds.join(","), "6,7,8,9,10");
    }
    function test_missing_or_out_of_range_workspace_never_uses_global_focus() {
      setWorkspace(secondMonitor, null);
      verifyActive(root.second, 0);
      setWorkspace(secondMonitor, {id: 11});
      verifyActive(root.second, 11);
      compare(root.second.naturalContentWidth, 235);
      verifyActive(root.first, 1);
      secondMonitor.lastIpcObject = null;
      verifyActive(root.second, 0);
    }
    function test_active_workspace_can_arrive_before_the_workspace_list() {
      root.second.workspaces = [];
      verifyActive(root.second, 6);
      compare(label(root.second, 6).text, "󰮯");
      compare(root.second.expandedImplicitWidth, 368);
    }
    function test_special_slot_is_local_and_keeps_the_normal_pacman() {
      secondMonitor.lastIpcObject = {
        activeWorkspace: {id: 6}, specialWorkspace: {id: -1, name: "special:Chat"}
      };
      root.first.syncSpecialWorkspace(false);
      root.second.syncSpecialWorkspace(false);
      verify(!root.first.specialWorkspaceVisible);
      verify(root.second.specialWorkspaceVisible);
      compare(root.second.specialSlotName, "Chat");
      verifyActive(root.first, 1);
      verifyActive(root.second, 6);
      compare(root.first.implicitWidth, 272);
      compare(root.second.implicitWidth, 368);
      secondMonitor.lastIpcObject = {
        activeWorkspace: {id: 6}, specialWorkspace: {id: 0, name: ""}
      };
      root.second.syncSpecialWorkspace(false);
      compare(root.second.implicitWidth, 272);
      verifyActive(root.second, 6);
    }
    function test_external_output_always_uses_the_first_five_slots() {
      secondMonitor.name = "HDMI-A-1";
      setWorkspace(secondMonitor, {id: 10});
      verifyActive(root.second, 10);
      compare(root.second.workspaceIds.join(","), "1,2,3,4,5");
      setWorkspace(secondMonitor, {id: 4});
      verifyActive(root.second, 4);
      compare(root.second.workspaceIds.join(","), "1,2,3,4,5");
    }
    function test_laptop_slots_follow_disconnect_and_reconnect() {
      root.second.monitors = [secondMonitor];
      setWorkspace(secondMonitor, workspaceThree);
      compare(root.second.workspaceIds.join(","), "1,2,3,4,5");
      verifyActive(root.second, 3);
      root.second.monitors = [firstMonitor, secondMonitor];
      setWorkspace(secondMonitor, workspaceSix);
      compare(root.second.workspaceIds.join(","), "6,7,8,9,10");
      verifyActive(root.second, 6);
      secondMonitor.name = "eDP-2";
      compare(root.second.workspaceIds.join(","), "6,7,8,9,10");
      root.second.monitors = [secondMonitor];
      compare(root.second.workspaceIds.join(","), "1,2,3,4,5");
    }
  }
}
