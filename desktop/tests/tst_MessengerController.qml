import QtQuick
import QtTest
import Quickshell

// No real accounts, compositor commands or desktop services.
ShellRoot {
  id: fixture
  property var controller: null
  QtObject {
    id: model
    property string selectedChat: ""
    property string selectedMessage: ""
    property string draftText: ""
    signal openRequested(string chatID, string messageID)
    function selectChat(chatID, messageID) { selectedChat = chatID; selectedMessage = messageID; }
  }
  Component.onCompleted: {
    const c = Qt.createComponent("file://" + Quickshell.shellDir + "/../shell/MessengerController.qml");
    if (c.status !== Component.Ready) { console.error(c.errorString()); Qt.exit(1); return; }
    controller = c.createObject(fixture, {beeperData: model, focusedMonitor: "A", availableMonitors: ["A", "B"]});
  }
  TestResult { id: results }
  TestCase {
    name: "MessengerController"
    when: fixture.controller !== null
    function cleanupTestCase() {
      console.log("MessengerController: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function monitor(name, workspace, special = 0) {
      return {name: name, lastIpcObject: {activeWorkspace: {id: workspace}, specialWorkspace: {id: special}}};
    }
    function init() {
      controller.hide(); controller.blocked = false; controller.focusedMonitor = "A";
      controller.availableMonitors = ["A", "B"];
      controller.monitors = [monitor("A", 1), monitor("B", 6)];
      model.selectedChat = ""; model.selectedMessage = ""; model.draftText = "";
    }
    function test_toggle_move_and_refocus_without_recreating_model() {
      const before = controller.focusSerial;
      controller.toggle(); verify(controller.visible); compare(controller.targetMonitor, "A");
      controller.toggle("B"); verify(controller.visible); compare(controller.targetMonitor, "B");
      compare(controller.focusSerial, before + 2); compare(controller.beeperData, model);
      controller.toggle("B"); verify(!controller.visible);
    }
    function test_notification_targets_message() {
      model.openRequested("chat", "message");
      verify(controller.visible); compare(controller.targetMonitor, "A");
      compare(model.selectedChat, "chat"); compare(model.selectedMessage, "message");
    }
    function test_polkit_prevents_open_but_does_not_close_existing_chat() {
      controller.blocked = true; controller.show(); verify(!controller.visible);
      controller.blocked = false; controller.show(); controller.blocked = true;
      verify(controller.visible);
      const before = controller.focusSerial;
      controller.show("B"); compare(controller.focusSerial, before); compare(controller.targetMonitor, "A");
    }
    function test_removing_target_monitor_closes_only_its_panel() {
      controller.show("B"); controller.availableMonitors = ["A"]; verify(!controller.visible);
      controller.show("A"); controller.availableMonitors = ["A", "C"]; verify(controller.visible);
    }
    function test_workspace_switch_preserves_conversation_and_draft() {
      model.openRequested("chat", "message"); model.draftText = "Keep this draft";
      controller.monitors = [monitor("A", 2), monitor("B", 6)];
      verify(!controller.visible);
      controller.show(); verify(controller.visible);
      compare(model.selectedChat, "chat"); compare(model.selectedMessage, "message");
      compare(model.draftText, "Keep this draft");
    }
    function test_refresh_and_other_monitor_workspace_do_not_close_chat() {
      controller.show();
      controller.monitors = [monitor("A", 1), monitor("B", 6)];
      verify(controller.visible);
      controller.monitors = [monitor("A", 1), monitor("B", 7)];
      verify(controller.visible);
    }
    function test_monitor_focus_switch_closes_chat() {
      controller.show(); controller.focusedMonitor = "B";
      verify(!controller.visible);
    }
    function test_explicit_transfer_tracks_destination_workspace() {
      controller.show(); controller.show("B"); controller.focusedMonitor = "B";
      verify(controller.visible);
      controller.monitors = [monitor("A", 2), monitor("B", 6)];
      verify(controller.visible);
      controller.monitors = [monitor("A", 2), monitor("B", 7)];
      verify(!controller.visible);
    }
    function test_special_workspace_switch_closes_chat() {
      controller.show();
      controller.monitors = [monitor("A", 1, -99), monitor("B", 6)];
      verify(!controller.visible);
      controller.show();
      controller.monitors = [monitor("A", 1), monitor("B", 6)];
      verify(!controller.visible);
    }
  }
}
