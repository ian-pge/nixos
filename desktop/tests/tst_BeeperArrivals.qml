import QtQuick
import QtTest
import Quickshell

// Real history/animation lifecycle, synthetic messages and fake transport.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  Window { id: window; width: 1280; height: 900; visible: true }
  TestResult { id: results }
  TestCase {
    name: "BeeperArrivals"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function message(index) {
      return {id: "m-" + index, chatID: "chat", senderName: "Friend", text: "Message " + index,
        timestamp: new Date(1700000000000 + index * 60000).toISOString()};
    }
    function history() { return findChild(panel, "beeperMessages"); }
    function settle() {
      tryCompare(panel, "restoringView", false);
      tryVerify(() => !history().loading && (!history().count || history().itemAtIndex(history().count - 1)?.viewportReady));
    }
    function load(rows, older = false) {
      beeperData.loadMessages(older);
      beeperData.respond("messages", {items: rows, hasMore: false});
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {width: 1280, height: 900, active: true, windowFocused: true, beeperData: beeperData});
      beeperData.chats = [{id: "chat", title: "Friends", network: "Telegram"}];
      beeperData.selectChat("chat");
      beeperData.respond("messages", {items: Array.from({length: 6}, (_, index) => message(index)), hasMore: false});
      settle();
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperArrivals: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_initial_history_and_older_pages_do_not_animate() {
      for (let index = 0; index < history().count; ++index)
        compare(history().itemAtIndex(index).arrivalMessageID, "");
      beeperData.hasOlderMessages = true; beeperData.oldestCursor = "older";
      load([message(-2), message(-1)], true); settle();
      compare(history().count, 8);
      for (let index = 0; index < history().count; ++index)
        compare(history().itemAtIndex(index).arrivalMessageID, "");
    }
    function test_new_visible_message_animates_without_changing_layout() {
      load([message(6)]); settle();
      const row = history().itemAtIndex(6);
      compare(row.arrivalMessageID, "m-6");
      verify(row.inVisibleViewport);
      compare(history().itemAtIndex(5).arrivalMessageID, "");
      const height = history().contentHeight, y = row.y;
      tryCompare(row, "arriving", false);
      compare(row.opacity, 1); compare(history().contentHeight, height); compare(row.y, y);
      load([Object.assign({}, message(6), {isUnread: false})]); settle(); wait(30);
      compare(history().itemAtIndex(6), row);
      verify(!row.arriving, "Read-state refreshes must not replay the arrival");
    }
    function test_first_new_message_after_an_empty_initial_history_animates() {
      beeperData.chats = beeperData.chats.concat([{id: "empty", title: "Empty conversation", network: "Telegram"}]);
      beeperData.selectChat("empty");
      compare(panel.arrivalReadyChatID, "", "Changing conversations must discard the old baseline");
      beeperData.respond("messages", {items: [], hasMore: false}); settle();
      compare(history().count, 0); compare(Object.keys(history().arrivalIds).length, 0);
      compare(panel.arrivalReadyChatID, "empty");
      load([Object.assign({}, message(0), {id: "empty-first", chatID: "empty"})]); settle();
      compare(history().count, 1);
      const row = history().itemAtIndex(0);
      compare(row.arrivalMessageID, "empty-first"); verify(row.inVisibleViewport);
      tryCompare(row, "arriving", false); compare(row.opacity, 1);
    }
    function test_burst_before_incubation_finishes_animates_each_new_message() {
      load([message(6)]); load([message(7)]); settle();
      compare(history().itemAtIndex(6).arrivalMessageID, "m-6");
      compare(history().itemAtIndex(7).arrivalMessageID, "m-7");
    }
    function test_reading_older_messages_does_not_jump_or_animate_new_arrivals() {
      load(Array.from({length: 40}, (_, index) => message(index))); settle(); wait(160);
      history().positionViewAtIndex(8, ListView.Beginning); wait(20);
      verify(!history().atYEnd);
      const y = history().contentY;
      load([message(40)]); settle();
      compare(history().itemAtIndex(40).arrivalMessageID, "");
      fuzzyCompare(history().contentY, y, 0.5);
    }
    function test_hidden_updates_and_reopening_do_not_replay_arrivals() {
      panel.active = false; panel.visible = false;
      load([message(6)]);
      panel.visible = true; panel.active = true; settle();
      for (let index = 0; index < history().count; ++index)
        compare(history().itemAtIndex(index).arrivalMessageID, "");
    }
  }
}
