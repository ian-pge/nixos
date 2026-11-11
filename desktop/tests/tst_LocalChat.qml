import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  Window { id: window; width: 1280; height: 900; visible: true; color: "#24273a" }
  TestResult { id: results }
  property var beeperData: null
  property var panel: null
  TestCase {
    name: "LocalChat"
    when: window.visible
    function create(file, parent, props) {
      const c = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(c.status, Component.Ready, c.errorString());
      const result = c.createObject(parent, props); verify(result !== null); return result;
    }
    function snapshot(revision, text, generating = true) {
      return {revision: revision, generating: generating, chat: Object.assign({}, beeperData.localAssistantChat),
        items: [{id: "reply", chatID: beeperData.localChatID, senderID: "assistant", senderName: "Qwen", text: text, plainText: text, timestamp: "2026-11-11T10:00:00Z"}]};
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {localAssistantEnabled: true, state: "offline"});
      beeperData.replaceChats([{id: "remote", title: "Contact"}]);
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true});
      beeperData.selectChat(beeperData.localChatID);
      beeperData.respond("messages", {items: [], revision: 0});
      wait(20);
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); panel.active = false; panel.destroy(); beeperData.destroy(); wait(0); }
    function cleanupTestCase() {
      console.log("LocalChat: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_local_chat_works_offline_and_preserves_next_draft() {
      verify(beeperData.currentChat.localAssistant);
      verify(!findChild(panel, "beeperConnectionSurface").visible);
      beeperData.draftText = "Bonjour Qwen";
      beeperData.sendMessage();
      compare(beeperData.requests.filter(r => r.method === "send")[0].params.chatID, beeperData.localChatID);
      beeperData.draftText = "Next message";
      beeperData.acceptLine(JSON.stringify({event: "ollamaChanged", data: snapshot(1, "Bonjour")}));
      beeperData.respond("send", {});
      compare(beeperData.draftText, "Next message");
      verify(beeperData.localGenerating);
      beeperData.sendMessage();
      compare(beeperData.requests.filter(r => r.method === "send").length, 0);
      verify(!panel.canPickAttachment); verify(!panel.canStartRecording);
      const action = findChild(panel, "beeperComposerAction");
      verify(action.enabled); action.clicked();
      compare(beeperData.requests.filter(r => r.method === "ollamaCancel").length, 1);
    }
    function test_streams_do_not_touch_other_chat_or_its_draft() {
      beeperData.draftText = "Local draft";
      beeperData.selectChat("remote"); beeperData.respond("messages", {items: [{id: "remote-message", text: "Private"}]});
      beeperData.draftText = "Private draft";
      beeperData.applyLocalSnapshot(snapshot(3, "Local reply"));
      compare(beeperData.currentChatID, "remote"); compare(beeperData.messages[0].text, "Private");
      compare(beeperData.draftText, "Private draft");
      beeperData.selectChat(beeperData.localChatID);
      compare(beeperData.draftText, "Local draft");
    }
    function test_old_history_cannot_roll_back_streamed_reply() {
      beeperData.loadMessages(false);
      beeperData.applyLocalSnapshot(snapshot(10, "Newest reply", false));
      beeperData.respond("messages", {items: [{id: "reply", text: "Old"}, {id: "earlier", text: "History"}], revision: 2, hasMore: true, oldestCursor: "50"});
      compare(beeperData.messages.find(m => m.id === "reply").plainText, "Newest reply");
      verify(beeperData.messages.some(m => m.id === "earlier")); verify(beeperData.hasOlderMessages);
      beeperData.applyLocalSnapshot(snapshot(4, "Stale", true));
      verify(!beeperData.localGenerating);
      compare(beeperData.messages.find(m => m.id === "reply").plainText, "Newest reply");
    }
    function test_local_conversation_available_without_beeper_token() {
      beeperData.clearSelection(); beeperData.state = "needs-token";
      const connection = findChild(panel, "beeperConnectionSurface"); verify(connection.visible);
      const button = findChild(panel, "beeperLocalChat"); verify(button.visible);
      button.clicked(); compare(beeperData.currentChatID, beeperData.localChatID); verify(!connection.visible);
    }
    function test_remote_catalog_does_not_remove_local_selection() {
      beeperData.draftText = "Keep my local draft";
      beeperData.commitChatRows([{id: "remote", title: "Contact", unreadCount: 2}], ++beeperData.chatStateSequence, "states");
      compare(beeperData.currentChatID, beeperData.localChatID);
      compare(beeperData.draftText, "Keep my local draft");
      compare(beeperData.unreadConversationCount("all"), 1);
    }
    function test_render_local_reply() {
      const result = snapshot(20, "Bonjour ! Je suis Qwen, ton assistant local.\n\nTu peux me poser des questions en français ou en anglais.");
      result.items.unshift({id: "hello", chatID: beeperData.localChatID, isSender: true,
        text: "Salut Qwen, tu peux m'aider ?", timestamp: "2026-11-11T09:59:00Z"});
      beeperData.applyLocalSnapshot(result);
      tryCompare(panel.chatList, "count", 2, 5000, "Local and remote chat rows are visible");
      tryVerify(() => panel.composer.enabled, 5000, "Local composer is enabled");
      wait(300);
      const screenshot = Quickshell.env("QS_LOCAL_CHAT_SCREENSHOT");
      if (screenshot) grabImage(panel).save(screenshot);
    }
    function test_streamed_markdown_reflows_without_touching_draft() {
      const first = snapshot(30, "# Bonjour");
      first.items[0].markdownHTML = "<h1>Bonjour</h1>";
      beeperData.applyLocalSnapshot(first);
      const history = findChild(panel, "beeperMessages");
      tryVerify(() => history.count === 1 && !history.loading && !history.finishPending);
      const bubble = history.itemAtIndex(0), height = bubble.height;
      verify(bubble.markdownBody);
      beeperData.draftText = "Mon prochain message";
      const next = snapshot(31, "# Bonjour\n\nUne réponse plus longue.", false);
      next.items[0].markdownHTML = "<h1>Bonjour</h1><p>Une réponse plus longue.</p><ul><li>premier</li><li>second</li></ul><pre><code>du code\nsur deux lignes</code></pre>";
      beeperData.applyLocalSnapshot(next);
      tryVerify(() => bubble.height > height && !history.finishPending);
      compare(history.itemAtIndex(0), bubble);
      compare(beeperData.draftText, "Mon prochain message");
    }
  }
}
