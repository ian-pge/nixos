import QtQuick
import QtTest
import Quickshell

// Exercise the production navigation delay with an in-memory transport only.
ShellRoot {
  id: fixture
  property var beeperData: null
  TestResult { id: results }
  TestCase {
    name: "BeeperNavigation"
    function init() {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/fixtures/PagedBeeperData.qml");
      compare(component.status, Component.Ready, component.errorString());
      beeperData = component.createObject(fixture, {navigationLoadDelay: 90, deferDrafts: true});
      verify(beeperData !== null);
      beeperData.chats = [{id: "a"}, {id: "b"}, {id: "c"}];
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperNavigation: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function messages() { return beeperData.requests.filter(request => request.method === "messages"); }
    function test_fast_navigation_selects_immediately_and_loads_only_the_destination() {
      beeperData.selectChat("a", "", true);
      compare(beeperData.currentChatID, "a"); verify(beeperData.historyLoadPending);
      beeperData.draftText = "Keep A";
      wait(20); beeperData.selectChat("b", "", true);
      compare(beeperData.localDrafts.a.text, "Keep A");
      beeperData.draftText = "Keep B";
      wait(20); beeperData.selectChat("c", "", true);
      compare(beeperData.currentChatID, "c"); compare(messages().length, 0);
      compare(beeperData.localDrafts.b.text, "Keep B");
      tryVerify(() => messages().length === 1);
      compare(messages()[0].params.chatID, "c"); verify(!beeperData.historyLoadPending);
      beeperData.respond("messages", {items: [{id: "last", chatID: "c", text: "Destination"}], hasMore: false});
      compare(beeperData.messages[0].chatID, "c");
      beeperData.selectChat("a", "", true);
      compare(beeperData.draftText, "Keep A");
      verify(!beeperData.requests.some(request => ["read", "unread", "send"].includes(request.method)));
    }
    function test_notification_target_bypasses_pending_navigation() {
      beeperData.selectChat("a", "", true);
      compare(messages().length, 0);
      beeperData.selectChat("a", "target");
      compare(messages().length, 1); verify(!beeperData.historyLoadPending);
      compare(beeperData.targetMessageID, "target");
      wait(120); compare(messages().length, 1, "The old timer must not issue a second request");
    }
    function test_late_reply_and_canceled_selection_never_fill_another_chat() {
      beeperData.selectChat("a"); compare(messages().length, 1);
      beeperData.selectChat("b", "", true);
      beeperData.respond("messages", {items: [{id: "old", chatID: "a"}], hasMore: false});
      compare(beeperData.messages.length, 0); compare(beeperData.currentChatID, "b");
      beeperData.clearSelection(); wait(120);
      compare(messages().length, 0); compare(beeperData.currentChatID, "");
      verify(!beeperData.historyLoadPending);
    }
    function test_notification_during_an_inflight_load_keeps_its_target() {
      beeperData.selectChat("a");
      compare(messages().length, 1);
      let publications = 0;
      beeperData.messagesLoaded.connect(() => ++publications);
      beeperData.selectChat("a", "target");
      compare(publications, 0, "An unfinished page must not be presented as a missing target");
      compare(beeperData.targetMessageID, "target");
      beeperData.respond("messages", {items: [{id: "target", chatID: "a"}], hasMore: false});
      compare(publications, 1);
    }
    function test_disconnect_cancels_a_pending_history_request() {
      beeperData.selectChat("a", "", true);
      beeperData.state = "offline"; wait(120);
      compare(messages().length, 0); verify(!beeperData.historyLoadPending);
    }
    function test_explicit_refresh_flushes_the_pending_load_once() {
      beeperData.selectChat("a", "", true);
      beeperData.loadMessages(false);
      compare(messages().length, 1); verify(!beeperData.historyLoadPending);
      wait(120); compare(messages().length, 1);
      beeperData.respond("messages", null, {message: "Unavailable"});
      verify(beeperData.messagesPaginationBlocked); verify(!beeperData.loadingMessages);
    }
  }
}
