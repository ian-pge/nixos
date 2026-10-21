import Quickshell
import QtQuick
import QtTest

ShellRoot {
  id: root
  property var first: null
  property var second: null
  property var theme: null

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
    theme = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../ui/Theme.js" as T; QtObject { property var library: T }', root).library;
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
    function slotHeight() { return 28 * root.theme.barScale; }
    function activeWidth() { return slotHeight() + root.theme.barSize(32); }
    function baseWidth(count = 5) { return (count - 1) * slotHeight() + activeWidth() + 2 * root.theme.barOutlineInset(); }
    function setWorkspace(monitor, workspace) {
      monitor.activeWorkspace = workspace;
      monitor.lastIpcObject = {
        activeWorkspace: workspace === null ? null : {id: workspace.id},
        specialWorkspace: {id: 0, name: ""}
      };
    }
    function verifyActive(widget, activeId, count = 5) {
      compare(widget.activeWorkspaceId, activeId);
      compare(widget.workspaceIds.length, count);
      compare(widget.workspaceCount, count);
      for (let id = 1; id <= 10; id++) {
        const item = button(widget, id);
        if (!widget.workspaceIds.includes(id)) {
          verify(item === null, "Other monitor's slots must not appear");
          continue;
        }
        verify(item !== null, "Every assigned workspace must have a slot");
        compare(item.active, id === activeId);
        tryCompare(item, "width", id === activeId ? activeWidth() : slotHeight());
        compare(item.height, slotHeight());
        compare(label(widget, id).font.pixelSize, root.theme.barSize(16), "Workspace glyphs follow the shared bar scale");
        fuzzyCompare(item.mapToItem(widget, 0, item.height / 2).y, widget.height / 2, 0.01);
        compare(item.children[0].radius, item.height / 2);
        if (!item.active) compare(item.width, item.height, "Inactive hover targets must remain circular");
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
        compare(widget.naturalContentWidth, 4 * slotHeight() + activeWidth());
        compare(widget.baseImplicitWidth, baseWidth());
        compare(widget.expandedImplicitWidth, baseWidth() + slotHeight());
      }
      verifyActive(root.first, 1);
      verifyActive(root.second, 6);
    }
    function test_compact_outer_insets_and_curves_are_concentric() {
      const inset = root.theme.barOutlineInset();
      for (const widget of [root.first, root.second]) {
        // Ten slots keep their natural width independently of the panel limit.
        if (widget === root.second) widget.monitors = [secondMonitor];
        widget.width = Qt.binding(() => widget.implicitWidth);
        try {
          for (const id of [widget.workspaceIds[0], widget.workspaceIds[widget.workspaceCount - 1]]) {
            setWorkspace(widget.monitor, {id: id});
            wait(450);
            const first = button(widget, widget.workspaceIds[0]);
            const last = button(widget, widget.workspaceIds[widget.workspaceCount - 1]);
            const left = first.mapToItem(widget, 0, 0);
            const right = last.mapToItem(widget, last.width, 0);
            fuzzyCompare(left.x, inset, 0.01, "Left margin matches the shared outline inset");
            fuzzyCompare(widget.width - right.x, inset, 0.01, "Right margin matches the shared outline inset");
            fuzzyCompare(left.y, inset, 0.01, "Top margin equals the side margins");
            fuzzyCompare(widget.height - left.y - first.height, inset, 0.01, "Bottom margin equals the side margins");
            fuzzyCompare(left.x + first.height / 2, widget.height / 2, 0.01, "Left curves share their center");
            fuzzyCompare(right.x - last.height / 2, widget.width - widget.height / 2, 0.01, "Right curves share their center");
          }
        } finally { widget.width = Qt.binding(() => widget.implicitWidth); }
      }
    }
    function test_changing_one_workspace_does_not_change_the_other_bar() {
      setWorkspace(secondMonitor, workspaceSeven);
      verifyActive(root.first, 1);
      verifyActive(root.second, 7);
      compare(label(root.second, 7).text, "󰮯");
      compare(label(root.second, 6).text, "󰊠");
      compare(root.second.expandedImplicitWidth, baseWidth() + slotHeight());
    }
    function test_hover_is_circular_and_matches_the_shared_ring_margin() {
      const widget = root.first;
      compare(widget.contentInset, root.theme.barOutlineInset());
      const active = button(widget, 1), pink = findChild(active, "workspaceHighlight");
      compare(pink.height, 28 * root.theme.barScale);
      compare(pink.width - pink.height, root.theme.barSize(32));
      for (const id of [2, 3]) {
        const item = button(widget, id), highlight = findChild(item, "workspaceHighlight");
        mouseMove(item, item.width / 2, item.height / 2);
        tryCompare(item, "hovered", true);
        compare(highlight.width, highlight.height);
        compare(highlight.height, pink.height);
        compare(highlight.radius, highlight.height / 2);
        fuzzyCompare(highlight.mapToItem(widget, 0, 0).y, widget.contentInset, 0.01);
        fuzzyCompare(widget.height - highlight.mapToItem(widget, 0, highlight.height).y,
          widget.contentInset, 0.01);
      }
    }
    function test_pacman_stays_centered_through_animation() {
      for (const workspace of [workspaceThree, workspaceOne]) {
        setWorkspace(firstMonitor, workspace);
        const item = button(root.first, workspace.id);
        const glyph = label(root.first, workspace.id);
        let sawIntermediateWidth = false;
        for (let frame = 0; frame < 30; frame++) {
          wait(16);
          if (item.width > root.first.workspaceButtonHeight
              && item.width < root.first.activeButtonWidth)
            sawIntermediateWidth = true;
          // Check the rendered geometry, including the last fractional width
          // and the final frame where rounded anchors used to jump.
          fuzzyCompare(glyph.x + glyph.width / 2, item.width / 2, 0.01,
            "Frame " + frame + ": glyph center=" + (glyph.x + glyph.width / 2)
            + ", button center=" + item.width / 2);
        }
        verify(sawIntermediateWidth, "Must check the animation, not only its endpoint");
        compare(item.width, root.first.activeButtonWidth);
      }
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
      compare(root.first.expandedImplicitWidth, baseWidth() + slotHeight());
      compare(root.second.expandedImplicitWidth, baseWidth() + slotHeight());
    }
    function test_monitor_can_disconnect_or_be_reassigned() {
      root.first.monitor = null;
      verifyActive(root.first, 0);
      compare(root.first.monitorName, "");
      verifyActive(root.second, 6);
      compare(root.first.naturalContentWidth, 5 * slotHeight());
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
      compare(root.second.naturalContentWidth, 5 * slotHeight());
      verifyActive(root.first, 1);
      secondMonitor.lastIpcObject = null;
      verifyActive(root.second, 0);
    }
    function test_active_workspace_can_arrive_before_the_workspace_list() {
      root.second.workspaces = [];
      verifyActive(root.second, 6);
      compare(label(root.second, 6).text, "󰮯");
      compare(root.second.expandedImplicitWidth, baseWidth() + slotHeight());
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
      compare(root.first.implicitWidth, baseWidth());
      compare(root.second.implicitWidth, baseWidth() + root.second.specialSlotWidth);
      secondMonitor.lastIpcObject = {
        activeWorkspace: {id: 6}, specialWorkspace: {id: 0, name: ""}
      };
      root.second.syncSpecialWorkspace(false);
      compare(root.second.implicitWidth, baseWidth());
      verifyActive(root.second, 6);
    }
    function test_special_capsule_fits_text_and_joins_workspace_row() {
      const widget = root.second;
      const slot = findChild(widget, "specialWorkspaceSlot");
      const text = findChild(widget, "specialWorkspaceLabel");
      const previous = button(widget, 9), last = button(widget, 10);
      for (const name of ["A", "Chat", "Terminal"]) {
        widget.setSpecialWorkspace("special:" + name, false);
        compare(text.text, name);
        compare(text.font.pixelSize, root.theme.barSize(13));
        tryCompare(slot, "width", Math.max(slotHeight(), text.implicitWidth + root.theme.barSize(12)));
        compare(slot.height, slotHeight());
        fuzzyCompare(slot.mapToItem(widget, 0, slot.height / 2).y, widget.height / 2, 0.01);
        compare(slot.radius, slot.height / 2);
        compare(widget.implicitWidth, widget.baseImplicitWidth + slot.width);
        verify(text.width <= slot.width - root.theme.barSize(12));
        const previousEnd = previous.mapToItem(widget, previous.width, 0).x;
        const lastStart = last.mapToItem(widget, 0, 0).x;
        const lastEnd = last.mapToItem(widget, last.width, 0).x;
        const specialStart = slot.mapToItem(widget, 0, 0).x;
        fuzzyCompare(specialStart - lastEnd, lastStart - previousEnd, 0.01);
        fuzzyCompare(widget.width - specialStart - slot.width, root.theme.barOutlineInset(), 0.01);
        const specialTop = slot.mapToItem(widget, 0, 0).y;
        fuzzyCompare(specialTop, root.theme.barOutlineInset(), 0.01);
        fuzzyCompare(widget.height - specialTop - slot.height, root.theme.barOutlineInset(), 0.01);
        fuzzyCompare(specialStart + slot.width - slot.radius, widget.width - widget.height / 2, 0.01);
      }
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
      compare(root.second.workspaceIds.join(","), "1,2,3,4,5,6,7,8,9,10");
      verifyActive(root.second, 3, 10);
      compare(root.second.baseImplicitWidth, baseWidth(10));
      setWorkspace(secondMonitor, {id: 10});
      verifyActive(root.second, 10, 10);
      compare(label(root.second, 10).text, "󰮯");
      root.second.monitors = [firstMonitor, secondMonitor];
      setWorkspace(secondMonitor, workspaceSix);
      compare(root.second.workspaceIds.join(","), "6,7,8,9,10");
      verifyActive(root.second, 6);
      secondMonitor.name = "eDP-2";
      compare(root.second.workspaceIds.join(","), "6,7,8,9,10");
      root.second.monitors = [secondMonitor];
      compare(root.second.workspaceIds.join(","), "1,2,3,4,5,6,7,8,9,10");
      verifyActive(root.second, 6, 10);
    }
    function test_mirrored_external_output_does_not_reduce_laptop_slots() {
      root.second.monitors = [secondMonitor, {
        name: "HDMI-A-1", lastIpcObject: {mirrorOf: "eDP-1"}
      }];
      verifyActive(root.second, 6, 10);
    }
  }
}
