import QtQuick
import QtTest
import Quickshell

// Only fake requests and fictional messages; no API, account or real typing.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  property var search: null
  property var input: null
  property var history: []
  property string stage: ""
  Window { id: window; width: 1280; height: 900; visible: true }
  SignalSpy { id: closed; target: fixture.panel; signalName: "closeRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperSearch"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function pending(method) { return beeperData.requests.filter(request => request.method === method); }
    function request(method) { tryVerify(() => pending(method).length > 0, 1500); return pending(method)[0]; }
    function init() {
      fixture.stage = "init";
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {width: 1280, height: 900, beeperData: beeperData, active: true, windowFocused: true});
      beeperData.chats = [{id: "chat-a", title: "First", network: "WhatsApp"}, {id: "chat-b", title: "Second", network: "Telegram"}];
      beeperData.selectChat("chat-a");
      history = [];
      for (let i = 0; i < 40; ++i) history.push({id: "message-" + i, chatID: "chat-a", senderName: "Contact",
        text: "Message " + i, timestamp: new Date(1700000000000 + i * 60000).toISOString()});
      beeperData.respond("messages", {items: history, hasMore: false});
      tryCompare(panel, "restoringView", false);
      search = findChild(panel, "beeperSearchController"); input = findChild(panel, "beeperMessageSearchInput");
      verify(search !== null); verify(input !== null);
      panel.focusNavigation(); closed.clear(); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName, fixture.stage,
        JSON.stringify({index: search?.index, selected: panel?.messageIndex, count: search?.results.length,
          more: search?.hasMore, loading: search?.loading, error: search?.errorText, failedPage: search?.failedPage,
          pending: pending("search").map(operation => operation.params), focus: input?.activeFocus}));
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperSearch: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function start(query = "Message") {
      keyClick(Qt.Key_Slash, Qt.ControlModifier);
      tryVerify(() => input.activeFocus);
      search.query = query;
      return request("search");
    }
    function oldMatch() { return {id: "old-match", chatID: "chat-a", text: "Old Message", timestamp: "2020-01-01T10:00:00Z"}; }
    function prepareOlderSearch() {
      start();
      beeperData.hasOlderMessages = true; beeperData.oldestCursor = "history-0";
      beeperData.respond("search", {items: [oldMatch()], hasMore: false});
      keyClick(Qt.Key_Return); verify(panel.locatingSearchResult);
      request("messages");
    }
    function test_ctrl_slash_preserves_draft_and_typing_is_never_vim_navigation() {
      panel.compose(); panel.composer.text = "Keep my draft";
      keyClick(Qt.Key_Slash, Qt.ControlModifier); tryVerify(() => input.activeFocus);
      keyClick(Qt.Key_N); keyClick(Qt.Key_J); keyClick(Qt.Key_K);
      compare(search.query, "njk"); compare(beeperData.currentChatID, "chat-a"); compare(panel.messageIndex, -1);
      const operation = request("search");
      compare(operation.params.chatID, "chat-a"); compare(operation.params.query, "njk"); verify(operation.quiet);
      compare(beeperData.draftText, "Keep my draft"); compare(pending("send").length, 0);
      keyClick(Qt.Key_Escape); verify(!search.opened); compare(search.query, ""); compare(closed.count, 0);
      beeperData.respond("search", {items: [history[10]], hasMore: false}); compare(search.results.length, 0);
    }
    function test_design_preview_search_handles_captionless_media_and_chat_scope() {
      const demo = create("../features/messenger/BeeperData.qml", fixture, {demo: true});
      try {
        demo.demoMessages.extra = [{id: "other", chatID: "other-chat", text: "atelier dimanche"},
          {id: "file", chatID: "studio", attachments: [{type: "img"}]}];
        let response = null;
        demo.request("search", {chatID: "studio", query: "dimanche atelier"}, result => { response = result; });
        tryVerify(() => response !== null);
        compare(response.items.length, 1); compare(response.items[0].chatID, "studio");
        compare(response.items[0].id, "1"); verify(!response.hasMore);
      } finally { demo.destroy(); }
    }
    function test_enter_and_vim_keys_select_matches_without_switching_chats() {
      start();
      beeperData.respond("search", {items: [history[10], history[30]], hasMore: false});
      keyClick(Qt.Key_Return); tryCompare(panel, "messageIndex", 30); verify(!input.activeFocus);
      compare(findChild(findChild(panel, "beeperMessages").itemAtIndex(30), "beeperMessageSelection").width, 12);
      keyClick(Qt.Key_N); compare(panel.messageIndex, 10);
      keyClick(Qt.Key_N, Qt.ShiftModifier); compare(panel.messageIndex, 30);
      keyClick(Qt.Key_J); compare(panel.messageIndex, 10);
      keyClick(Qt.Key_K); compare(panel.messageIndex, 30);
      keyClick(Qt.Key_J, Qt.ControlModifier); compare(panel.messageIndex, 10);
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 30);
      compare(search.counter, "1 / 2"); compare(beeperData.currentChatID, "chat-a"); compare(pending("read").length, 0);
      compare(pending("unread").length, 0, "n navigates search matches without marking the conversation unread");
      keyClick(Qt.Key_Escape); verify(!search.opened); compare(panel.messageIndex, -1); compare(closed.count, 0);
    }
    function test_search_is_to_the_right_of_the_name_without_taking_history_height() {
      const header = findChild(panel, "beeperConversationHeader"), bar = findChild(panel, "beeperMessageSearchBar");
      const title = findChild(panel, "beeperChatTitle"), historyView = findChild(panel, "beeperMessages");
      for (const width of [1280, 800, 700]) {
        panel.closeConversationSearch(); panel.width = width; wait(30);
        const before = historyView.height;
        panel.openConversationSearch(); wait(30);
        compare(bar.parent, header);
        const titlePoint = title.mapToItem(header, 0, 0);
        verify(bar.x >= titlePoint.x + title.width, "Search belongs beside the name, never below it");
        verify(bar.x + bar.width <= header.width + 0.5);
        verify(bar.y >= 0 && bar.y + bar.height <= header.height + 0.5);
        verify(input.width > 60, "The compact field remains usable");
        fuzzyCompare(historyView.height, before, 0.5);
      }
    }
    function test_every_matching_message_is_highlighted_then_escape_restores_plain_text() {
      start("message"); beeperData.respond("search", {items: [history[10], history[30]], hasMore: false});
      keyClick(Qt.Key_Return);
      const list = findChild(panel, "beeperMessages");
      for (const index of [30, 10]) {
        const row = list.itemAtIndex(index), highlight = findChild(row, "beeperMessageHighlights");
        compare(panel.messageIndex, index); compare(row.searchQuery, "message");
        tryVerify(() => highlight.visible);
        compare(highlight.textFormat, Text.RichText);
        verify(highlight.text.includes("background-color:#eed49f"));
        if (index === 30) keyClick(Qt.Key_N);
      }
      compare(panel.messageIndex, 10);
      keyClick(Qt.Key_Escape);
      for (const index of [10, 30]) {
        const body = findChild(list.itemAtIndex(index), "messageBody");
        compare(body.textFormat, Text.PlainText); compare(body.text, history[index].text);
        verify(!findChild(list.itemAtIndex(index), "beeperMessageHighlights").visible);
      }
    }
    function test_enter_before_response_navigates_when_the_query_finishes() {
      start(); keyClick(Qt.Key_Return); verify(search.navigateWhenReady);
      beeperData.respond("search", {items: [history[20]], hasMore: false});
      compare(panel.messageIndex, 20); verify(!search.loading); verify(!panel.locatingSearchResult);
    }
    function test_older_search_pages_are_automatic_and_can_retry_without_duplicate_results() {
      fixture.stage = "initial";
      start(); beeperData.respond("search", {items: [history[30], history[20]], hasMore: true, oldestCursor: "opaque + /"});
      keyClick(Qt.Key_Return); keyClick(Qt.Key_N); compare(panel.messageIndex, 20);
      fixture.stage = "next page";
      keyClick(Qt.Key_N);
      const next = request("search"); compare(next.params.cursor, "opaque + /"); compare(next.params.direction, "before");
      beeperData.respond("search", null, {message: "offline"}); verify(!!search.errorText);
      wait(300); compare(pending("search").length, 0);
      fixture.stage = "retry";
      keyClick(Qt.Key_Return); compare(request("search").params.cursor, "opaque + /");
      beeperData.respond("search", {items: [history[20], history[10]], hasMore: false});
      fixture.stage = "retry completed";
      compare(search.results.length, 3); compare(panel.messageIndex, 10);
      fixture.stage = "wrap";
      keyClick(Qt.Key_N); compare(panel.messageIndex, 30);
      keyClick(Qt.Key_N, Qt.ShiftModifier); compare(panel.messageIndex, 10);
    }
    function test_late_queries_and_other_chats_cannot_replace_current_results() {
      start("first"); search.query = "second";
      tryVerify(() => pending("search").length === 2);
      beeperData.respond("search", {items: [history[30]], hasMore: false}); compare(search.results.length, 0); verify(search.loading);
      beeperData.respond("search", {items: [history[20], {id: "wrong", chatID: "chat-b", text: "second"}], hasMore: false});
      compare(search.results.length, 1); compare(search.results[0].id, "message-20");
      search.query = "third"; request("search"); panel.chooseChat(1);
      beeperData.respond("search", {items: [history[10]], hasMore: false});
      verify(!search.opened); compare(search.results.length, 0); compare(beeperData.currentChatID, "chat-b");
    }
    function test_old_match_loads_context_past_twenty_pages_with_only_real_cursors() {
      prepareOlderSearch();
      for (let page = 0; page < 22; ++page) {
        const operation = request("messages"); compare(operation.params.cursor, "history-" + page);
        compare(operation.params.direction, "before");
        beeperData.respond("messages", {items: [], oldestCursor: "history-" + (page + 1), hasMore: true});
      }
      request("messages"); beeperData.respond("messages", {items: [oldMatch()], hasMore: false});
      tryVerify(() => panel.selectedMessage?.id === "old-match");
      verify(!panel.locatingSearchResult); compare(search.errorText, ""); compare(beeperData.lastError, "");
    }
    function test_escape_cancels_history_lookup_and_keeps_the_conversation_open() {
      prepareOlderSearch(); keyClick(Qt.Key_Escape);
      verify(!panel.locatingSearchResult); verify(!search.opened); compare(beeperData.targetMessageID, "");
      beeperData.respond("messages", {items: [], oldestCursor: "history-1", hasMore: true});
      wait(250); compare(pending("messages").length, 0); compare(closed.count, 0);
    }
    function test_history_errors_stop_and_enter_can_retry() {
      prepareOlderSearch();
      beeperData.respond("messages", null, {message: "offline"});
      verify(!panel.locatingSearchResult); verify(!!search.errorText);
      wait(200); compare(pending("messages").length, 0);
      keyClick(Qt.Key_Return); request("messages");
      beeperData.respond("messages", {items: [oldMatch()], hasMore: false});
      tryVerify(() => panel.selectedMessage?.id === "old-match");
    }
    function test_editing_query_cancels_previous_history_target() {
      prepareOlderSearch(); search.query = "different";
      verify(!panel.locatingSearchResult); compare(beeperData.targetMessageID, "");
      beeperData.respond("messages", {items: [oldMatch()], hasMore: false});
      wait(20); verify(panel.selectedMessage?.id !== "old-match");
    }
    function test_notification_target_in_another_chat_survives_search_cancellation() {
      prepareOlderSearch();
      beeperData.selectChat("chat-b", "notification-target");
      verify(!search.opened); verify(!panel.locatingSearchResult);
      compare(beeperData.targetMessageID, "notification-target");
      beeperData.respond("messages", {items: [oldMatch()], hasMore: false});
      beeperData.respond("messages", {items: [{id: "notification-target", chatID: "chat-b", text: "New conversation"}], hasMore: false});
      tryVerify(() => panel.selectedMessage?.id === "notification-target");
      compare(beeperData.currentChatID, "chat-b");
    }
    function test_cursor_loop_and_empty_query_cannot_spin() {
      start(); beeperData.respond("search", {items: [history[30]], hasMore: true, oldestCursor: "same"});
      keyClick(Qt.Key_Return); keyClick(Qt.Key_N); request("search");
      beeperData.respond("search", {items: [history[30]], hasMore: true, oldestCursor: "same"});
      verify(!search.hasMore); wait(300); compare(pending("search").length, 0);
      search.query = "   "; wait(300); compare(pending("search").length, 0); compare(search.results.length, 0);
      keyClick(Qt.Key_Escape); panel.windowFocused = false;
      keyClick(Qt.Key_Slash, Qt.ControlModifier); verify(!search.opened);
    }
  }
}
