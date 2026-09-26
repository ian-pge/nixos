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
    function init() { controller.hide(); controller.blocked = false; controller.availableMonitors = ["A", "B"]; }
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
  }
}
