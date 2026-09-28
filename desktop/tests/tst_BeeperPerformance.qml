import QtQuick
import QtTest
import Quickshell

// The complete conversation UI, fake transport and synthetic messages only.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  property var hiddenPanel: null
  property bool measuring: false
  property real lastBeat: 0
  property real longestPause: 0
  readonly property string referenceSource: Quickshell.env("BEEPER_PERFORMANCE_SOURCE") || ""
  Window { id: window; width: 1280; height: 900; visible: true; color: "#181926" }
  Timer {
    interval: 16; repeat: true; running: fixture.measuring
    onTriggered: {
      const now = Date.now();
      if (fixture.lastBeat) fixture.longestPause = Math.max(fixture.longestPause, now - fixture.lastBeat);
      fixture.lastBeat = now;
    }
  }
  TestResult { id: results }
  TestCase {
    name: "BeeperPerformance"
    when: window.visible
    function create(path, parent, props) {
      const component = Qt.createComponent("file://" + path);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function initTestCase() {
      beeperData = create(Quickshell.shellDir + "/fixtures/PagedBeeperData.qml", fixture, {});
      beeperData.chats = Array.from({length: 40}, (_, index) => ({id: "chat-" + index,
        title: "Conversation " + index, network: "Telegram", type: "group",
        participants: {total: 3, items: [{id: "self", isSelf: true}, {id: "friend", fullName: "Friend"}]}}));
      const source = referenceSource || Quickshell.shellDir + "/../features/messenger/BeeperPanel.qml";
      panel = create(source, window.contentItem, {width: 1280, height: 900, active: true, windowFocused: true, beeperData: beeperData});
      hiddenPanel = create(source, window.contentItem, {width: 1280, height: 900, active: false, visible: false, beeperData: beeperData});
    }
    function cleanupTestCase() {
      panel.active = false; panel.destroy(); hiddenPanel.destroy(); beeperData.destroy();
      console.log("BeeperPerformance: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function messages(chatID, count) {
      return Array.from({length: count}, (_, index) => ({id: chatID + "-message-" + index, chatID: chatID,
        senderID: index % 3 ? "friend" : "self", senderName: "Friend", isSender: index % 3 === 0,
        text: index % 5 === 0 ? "A longer message with several lines.\n".repeat(5) : "A synthetic message " + index,
        timestamp: new Date(1700000000000 + index * 60000).toISOString()}));
    }
    function pendingMessages() { return beeperData.requests.filter(request => request.method === "messages"); }
    function test_large_history_keeps_the_event_loop_available() {
      tryVerify(() => pendingMessages().length > 0);
      beeperData.respond("messages", {items: messages(beeperData.currentChatID, 6), hasMore: false});
      tryCompare(panel, "restoringView", false); wait(100);
      panel.chooseChat(1);
      tryVerify(() => pendingMessages().length > 0);
      const batch = messages(beeperData.currentChatID, 150);
      fixture.lastBeat = Date.now(); fixture.longestPause = 0; fixture.measuring = true;
      const started = Date.now();
      beeperData.respond("messages", {items: batch, hasMore: false});
      const applyMs = Date.now() - started;
      tryCompare(panel, "restoringView", false, 10000);
      wait(150); fixture.measuring = false;
      const history = findChild(panel, "beeperMessages"), hidden = findChild(hiddenPanel, "beeperMessages");
      compare(history.count, 150);
      verify(history.itemAtIndex(149) !== null);
      console.log("Conversation performance:", JSON.stringify({messages: 150, applyMs: applyMs,
        settleMs: Date.now() - started, longestPauseMs: fixture.longestPause,
        hiddenMessages: hidden.count}));
      if (!referenceSource) compare(hidden.count, 0, "Hidden monitors must not build duplicate histories");
    }
    function test_rapid_navigation_loads_only_the_final_conversation() {
      beeperData.navigationLoadDelay = 90;
      let reads = 0;
      fixture.lastBeat = Date.now(); fixture.longestPause = 0; fixture.measuring = true;
      const started = Date.now();
      for (let index = 2; index < 14; ++index) {
        panel.chooseChat(index);
        compare(beeperData.currentChatID, "chat-" + index);
        wait(25);
        while (pendingMessages().length) {
          const request = pendingMessages()[0];
          ++reads;
          beeperData.respond("messages", {items: messages(request.params.chatID, 50), hasMore: false});
        }
      }
      if (!beeperData.messages.length) {
        tryVerify(() => pendingMessages().length > 0);
        const request = pendingMessages()[0]; ++reads;
        beeperData.respond("messages", {items: messages(request.params.chatID, 50), hasMore: false});
      }
      tryCompare(panel, "restoringView", false, 10000);
      wait(100); fixture.measuring = false;
      compare(beeperData.currentChatID, "chat-13");
      compare(beeperData.messages[0].chatID, "chat-13");
      console.log("Conversation performance:", JSON.stringify({selections: 12, historyRequests: reads,
        elapsedMs: Date.now() - started, longestPauseMs: fixture.longestPause}));
      if (!referenceSource) compare(reads, 1, "Intermediate conversations must not create histories or media decoders");
    }
    function test_switching_during_history_creation_discards_old_bubbles() {
      beeperData.navigationLoadDelay = 0;
      panel.chooseChat(20); tryVerify(() => pendingMessages().length > 0);
      beeperData.respond("messages", {items: messages("chat-20", 150), hasMore: false});
      wait(20);
      panel.chooseChat(21); tryVerify(() => pendingMessages().length > 0);
      beeperData.respond("messages", {items: messages("chat-21", 6), hasMore: false});
      tryCompare(panel, "restoringView", false, 10000);
      const history = findChild(panel, "beeperMessages");
      compare(history.count, 6);
      for (let index = 0; index < history.count; ++index)
        compare(history.itemAtIndex(index).message.chatID, "chat-21");
      if (!referenceSource) compare(history.createdCount, 6);
    }
  }
}
