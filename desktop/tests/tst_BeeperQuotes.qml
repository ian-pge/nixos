import QtQuick
import QtTest
import Quickshell

// Public-message retrieval is simulated. No account or real messages are read.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var views: []
  Window { id: window; width: 900; height: 700; visible: true }
  TestResult { id: results }
  TestCase {
    name: "BeeperQuotes"
    when: window.visible
    function create(file, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(window.contentItem, props);
      verify(item !== null); views.push(item); return item;
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", {});
      beeperData.currentChatID = "chat";
      beeperData.chats = [{id: "chat", title: "Group", type: "group"}];
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      for (let i = views.length - 1; i >= 0; --i) views[i].destroy();
      views = []; wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperQuotes: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function reply(outgoing) {
      return create("../features/messenger/BeeperMessage.qml", {width: 680, beeperData: beeperData,
        message: {id: outgoing ? "sent" : "received", text: "A reply", isSender: outgoing, linkedMessageID: "original"}});
    }
    function pending() { return beeperData.requests.filter(request => request.method === "message"); }
    function test_incoming_and_outgoing_replies_quote_author_and_plain_text_above_body() {
      beeperData.messages = [{id: "original", chatID: "chat", senderName: "Camille", text: "<b>Rich body</b>", plainText: "Quoted text 🌿"}];
      for (const outgoing of [false, true]) {
        const row = reply(outgoing), quote = findChild(row, "beeperQuote"), body = findChild(row, "messageBody");
        wait(20);
        verify(quote.visible); compare(quote.author, "Camille"); compare(quote.preview, "Quoted text 🌿");
        compare(findChild(quote, "beeperQuoteText").textFormat, Text.PlainText);
        verify(quote.y + quote.height <= body.y);
        compare(pending().length, 0);
      }
    }
    function test_offpage_original_is_fetched_once_without_inserting_history() {
      const first = reply(false), second = reply(true);
      tryVerify(() => pending().length === 1);
      compare(pending()[0].params.chatID, "chat"); compare(pending()[0].params.messageID, "original");
      verify(pending()[0].quiet);
      beeperData.respond("message", {id: "original", chatID: "chat", senderName: "Alex", text: "An older message"});
      tryCompare(findChild(first, "beeperQuote"), "preview", "An older message");
      compare(findChild(second, "beeperQuote").author, "Alex");
      compare(beeperData.messages.length, 0); compare(pending().length, 0);
    }
    function test_short_reply_does_not_reserve_the_entire_available_width() {
      beeperData.messages = [{id: "original", chatID: "chat", senderName: "Camille", text: "Short quote"}];
      for (const outgoing of [false, true]) {
        const row = reply(outgoing), bubble = findChild(row, "beeperMessageBubble"), quote = findChild(row, "beeperQuote");
        wait(20);
        verify(bubble.width < 300, "A short quote should fit its contents, just like other messages");
        verify(quote.implicitWidth <= quote.width);
        verify(quote.height > 0);
      }
    }
    function test_composer_previews_original_and_attachment_only_reply() {
      beeperData.messages = [{id: "original", chatID: "chat", isSender: true, attachments: [{type: "voice-note"}]}];
      beeperData.replyToMessageID = "original";
      const composer = create("../features/messenger/BeeperComposer.qml", {width: 650, beeperData: beeperData, active: true});
      const quote = findChild(composer, "beeperQuote");
      wait(20); verify(quote.visible); compare(quote.author, "You"); compare(quote.preview, "Voice message");
      beeperData.replyToMessageID = ""; verify(!quote.visible);
    }
    function test_deleted_original_and_missing_api_result_never_show_stale_text_or_retry_loop() {
      const row = reply(false), quote = findChild(row, "beeperQuote");
      tryVerify(() => pending().length === 1);
      beeperData.respond("message", {id: "original", chatID: "chat", text: "This will be deleted"});
      tryCompare(quote, "preview", "This will be deleted");
      beeperData.acceptLine(JSON.stringify({event: "messagesDeleted", data: {chatID: "chat", ids: ["original"]}}));
      compare(quote.preview, "Original message unavailable");
      wait(80); compare(pending().length, 0);
      beeperData.deletedMessageIDs = ({}); beeperData.invalidateQuotes();
      tryVerify(() => pending().length === 1);
      beeperData.respond("message", null, {code: "not_found", message: "Unavailable"});
      compare(quote.preview, "Original message unavailable");
      wait(80); compare(pending().length, 0); compare(beeperData.lastError, "");
    }
    function test_quote_errors_do_not_replace_chat_error_banner() {
      beeperData.lastError = "Existing unrelated error";
      beeperData.pending[100] = {method: "message", quiet: true};
      beeperData.acceptLine(JSON.stringify({id: 100, error: {code: "not_found", message: "Missing original"}}));
      compare(beeperData.lastError, "Existing unrelated error");
    }
    function test_late_original_response_cannot_cross_chat_boundaries() {
      beeperData.ensureQuote("original"); compare(pending().length, 1);
      beeperData.selectChat("another-chat");
      beeperData.respond("message", {id: "original", chatID: "chat", text: "Wrong conversation"});
      compare(beeperData.quote("original").state, "idle");
      beeperData.ensureQuote("original"); compare(pending().length, 1);
      compare(pending()[0].params.chatID, "another-chat");
      beeperData.respond("message", {id: "original", chatID: "another-chat", text: "Correct conversation"});
      compare(beeperData.quote("original").message.text, "Correct conversation");
    }
    function test_loaded_edits_and_hidden_originals_update_quotes() {
      beeperData.messages = [{id: "original", chatID: "chat", text: "Before"}];
      const row = reply(false), quote = findChild(row, "beeperQuote");
      compare(quote.preview, "Before");
      beeperData.messages = [{id: "original", chatID: "chat", text: "After"}];
      compare(quote.preview, "After");
      beeperData.messages = [{id: "original", chatID: "chat", text: "Hidden text", isHidden: true}];
      compare(quote.preview, "Original message unavailable");
    }
    function test_quote_respects_text_zoom_and_limits_long_preview() {
      beeperData.messages = [{id: "original", chatID: "chat", senderName: "Someone", text: "Long original message. ".repeat(200)}];
      const row = reply(false); row.width = 380; row.textScale = 1.8;
      const quote = findChild(row, "beeperQuote"), label = findChild(quote, "beeperQuoteText");
      wait(20); compare(label.maximumLineCount, 3); compare(label.font.pixelSize, 27);
      verify(quote.height < 180); verify(quote.width <= row.width);
    }
  }
}
