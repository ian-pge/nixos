import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  Window { id: window; width: 1280; height: 900; visible: true }
  TestResult { id: results }
  TestCase {
    name: "BeeperPagination"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props);
      verify(item !== null); return item;
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true});
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperPagination: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function chats(start, count, network) {
      const rows = [];
      for (let i = start; i < start + count; ++i)
        rows.push({id: "chat-" + i, title: "Conversation " + i, network: network || "Telegram"});
      return rows;
    }
    function messages(start, count) {
      const rows = [];
      for (let i = start; i < start + count; ++i)
        rows.push({id: "message-" + i, chatID: "chat-0", senderName: "Contact",
          text: "Message " + i + ": a little text for stable history geometry.",
          timestamp: new Date(1700000000000 + i * 60000).toISOString()});
      return rows;
    }
    function pending(method) { return beeperData.requests.filter(request => request.method === method); }
    function waitRequest(method) { tryVerify(() => pending(method).length === 1, 2000); return pending(method)[0]; }
    function seedHistory() {
      beeperData.chats = chats(0, 1); beeperData.selectChat("chat-0");
      beeperData.respond("messages", {items: messages(30, 30), oldestCursor: "history-30", hasMore: true});
      tryCompare(panel, "restoringView", false);
      wait(150);
      compare(pending("messages").length, 0, "Opening starts at the latest messages, not the oldest page");
    }
    function test_first_visible_chat_is_selected_when_initial_page_arrives_without_marking_read() {
      beeperData.networkFilter = "whatsapp";
      beeperData.refreshChats(false);
      compare(beeperData.currentChatID, ""); compare(pending("messages").length, 0);
      beeperData.respond("chats", {items: [
        {id: "archived", network: "WhatsApp", title: "Archived", isArchived: true},
        {id: "other-network", network: "Telegram", title: "Elsewhere"},
        {id: "first", network: "WhatsApp", title: "First visible", unreadCount: 3},
        {id: "second", network: "WhatsApp", title: "Second visible"}
      ], hasMore: false});
      tryCompare(beeperData, "currentChatID", "first"); compare(panel.chatIndex, 0);
      compare(waitRequest("messages").params.chatID, "first");
      beeperData.respond("messages", {items: [{id: "unread", chatID: "first", text: "Still unread", isUnread: true}], hasMore: false});
      wait(250); compare(beeperData.currentChat.unreadCount, 3);
      compare(pending("read").length, 0); compare(pending("messages").length, 0);
    }
    function test_cached_chats_are_selected_only_after_the_panel_stays_open() {
      panel.active = false;
      beeperData.chats = chats(0, 3);
      wait(20); compare(beeperData.currentChatID, "");
      panel.active = true; panel.active = false;
      wait(20); compare(beeperData.currentChatID, ""); compare(pending("messages").length, 0);
      panel.active = true;
      tryCompare(beeperData, "currentChatID", "chat-0");
      compare(waitRequest("messages").params.chatID, "chat-0");
    }
    function test_initial_selection_waits_for_a_matching_chat_and_connection() {
      beeperData.networkFilter = "whatsapp";
      beeperData.chats = chats(0, 2, "Telegram");
      wait(20); compare(beeperData.currentChatID, "");
      beeperData.state = "offline";
      beeperData.chats = beeperData.chats.concat(chats(2, 2, "WhatsApp"));
      wait(20); compare(beeperData.currentChatID, "");
      beeperData.state = "connected";
      tryCompare(beeperData, "currentChatID", "chat-2");
      compare(waitRequest("messages").params.chatID, "chat-2");
    }
    function test_explicit_open_and_existing_selection_win_over_default_selection() {
      panel.active = false; beeperData.chats = chats(0, 3);
      panel.active = true;
      panel.openChat("chat-2", "notification-target");
      wait(20); compare(beeperData.currentChatID, "chat-2");
      compare(waitRequest("messages").params.chatID, "chat-2");
      beeperData.respond("messages", {items: [{id: "notification-target", chatID: "chat-2", text: "Target"}], hasMore: false});
      beeperData.draftText = "Keep this conversation and draft";
      panel.active = false; panel.active = true; wait(30);
      compare(beeperData.currentChatID, "chat-2"); compare(panel.chatIndex, 2);
      compare(beeperData.draftText, "Keep this conversation and draft");
      compare(pending("messages").length, 0); compare(pending("read").length, 0);
    }
    function test_opening_scrolling_focus_and_new_messages_never_request_read() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      wait(250); compare(pending("read").length, 0);
      list.positionViewAtIndex(8, ListView.Beginning); panel.updateView();
      list.positionViewAtEnd(); panel.updateView(); wait(250);
      compare(pending("read").length, 0);
      panel.windowFocused = false; panel.windowFocused = true; wait(250);
      compare(pending("read").length, 0);
      beeperData.loadMessages(false);
      beeperData.respond("messages", {items: messages(60, 1), hasMore: false}); wait(250);
      compare(pending("read").length, 0);
    }
    function test_unread_errors_do_not_change_flags_and_success_refreshes_target_chat() {
      seedHistory();
      beeperData.chats = chats(0, 2).map(chat => Object.assign({}, chat, {unreadCount: 0, isMarkedUnread: false}));
      panel.focusNavigation(); keyClick(Qt.Key_N);
      compare(waitRequest("unread").params.chatID, "chat-0");
      verify(!beeperData.currentChat.isMarkedUnread, "Wait for the API before showing success");
      beeperData.respond("unread", null, {message: "Offline"}); wait(20);
      verify(!beeperData.currentChat.isMarkedUnread); compare(pending("chats").length, 0);
      keyClick(Qt.Key_N); compare(waitRequest("unread").params.chatID, "chat-0");
      beeperData.selectChat("chat-1");
      beeperData.respond("messages", {items: [], hasMore: false});
      beeperData.respond("unread", {});
      waitRequest("chats");
      beeperData.respond("chats", {items: beeperData.chats.map(chat => chat.id === "chat-0" ? Object.assign({}, chat, {isMarkedUnread: true}) : chat), hasMore: false});
      verify(beeperData.chats.find(chat => chat.id === "chat-0").isMarkedUnread);
      verify(!beeperData.currentChat.isMarkedUnread, "A delayed reply must not mark the newly selected chat");
    }
    function test_partial_unread_reply_preserves_conversation_metadata_and_filter_membership() {
      beeperData.chats = chats(0, 2, "Telegram"); beeperData.networkFilter = "telegram";
      panel.chooseChat(0); beeperData.respond("messages", {items: [], hasMore: false});
      panel.focusNavigation(); keyClick(Qt.Key_N); waitRequest("unread");
      beeperData.respond("unread", {id: "chat-0", unreadCount: 0, isMarkedUnread: true});
      compare(beeperData.currentChatID, "chat-0"); compare(beeperData.currentChat.title, "Conversation 0");
      compare(beeperData.currentChat.network, "Telegram"); verify(beeperData.currentChat.isMarkedUnread);
      verify(panel.filteredChats.some(chat => chat.id === "chat-0"));
    }
    function test_n_does_not_hide_a_conversation_reported_as_both_archived_and_manually_unread() {
      const original = {id: "chat-0", title: "Conversation", network: "Google Messages", isArchived: false, isMarkedUnread: false, unreadCount: 0};
      beeperData.chats = [original]; beeperData.networkFilter = "sms";
      panel.chooseChat(0); beeperData.respond("messages", {items: messages(0, 3), hasMore: false});
      tryCompare(panel, "restoringView", false); panel.focusNavigation();
      keyClick(Qt.Key_N); waitRequest("unread");
      // This flag combination was observed in both list and retrieve responses
      // from the real API. It is not a deletion or just a change in list order.
      const marked = Object.assign({}, original, {isArchived: true, isMarkedUnread: true});
      beeperData.respond("unread", marked); waitRequest("chats");
      beeperData.respond("chats", {items: [marked], hasMore: false});
      wait(40); panel.chatList.forceLayout();
      verify(panel.filteredChats.some(chat => chat.id === "chat-0"), "The manual unread marker must take precedence over archive filtering");
      compare(beeperData.currentChatID, "chat-0"); compare(beeperData.messages.length, 3);
      verify(beeperData.currentChat.isArchived, "Keep Beeper's archive state intact; do not silently unarchive it");
      const row = findChild(panel, "beeperChatRow-chat-0"); verify(row !== null); verify(row.unread);
      beeperData.refreshChats(false); beeperData.respond("chats", {items: [marked], hasMore: false});
      compare(panel.filteredChats.length, 1, "Subsequent refreshes must not hide it again");
    }
    function test_unread_header_counts_complete_conversations_per_network_not_loaded_messages() {
      beeperData.chats = [{id: "loaded", network: "Telegram", title: "Only loaded chat", unreadCount: 50}];
      waitRequest("unreadCounts");
      beeperData.respond("unreadCounts", {counts: {Telegram: 3, WhatsApp: 2, "Google Messages": 1, Signal: 2}});
      const counter = findChild(panel, "beeperUnreadConversationCount");
      compare(counter.text, "8 unread");
      beeperData.networkFilter = "telegram"; compare(counter.text, "3 unread");
      beeperData.networkFilter = "sms"; compare(counter.text, "1 unread");
      beeperData.networkFilter = "all"; panel.searchField.text = "No matching title";
      compare(counter.text, "8 unread", "Title search does not change the network's total");
    }
    function test_unread_counter_ignores_late_results_after_disconnect_and_retries_on_connect() {
      waitRequest("unreadCounts"); beeperData.respond("unreadCounts", {counts: {Telegram: 1}});
      beeperData.markChatUnread("target"); waitRequest("unread"); beeperData.respond("unread", {});
      waitRequest("unreadCounts"); beeperData.state = "offline";
      beeperData.respond("unreadCounts", {counts: {Telegram: 999}});
      verify(!beeperData.unreadCountsReady);
      const counter = findChild(panel, "beeperUnreadConversationCount"); verify(!counter.text.includes("999"));
      beeperData.state = "connected"; waitRequest("unreadCounts");
      beeperData.respond("unreadCounts", {counts: {Telegram: 2}});
      compare(counter.text, "2 unread");
    }
    function test_unread_counter_error_is_not_zero_and_event_refreshes_are_coalesced() {
      waitRequest("unreadCounts"); beeperData.respond("unreadCounts", null, {message: "Unavailable"});
      verify(!beeperData.unreadCountsReady); compare(beeperData.lastError, "");
      compare(findChild(panel, "beeperUnreadConversationCount").text, "— unread");
      wait(200); compare(pending("unreadCounts").length, 0);
      beeperData.scheduleUnreadCounts(true); waitRequest("unreadCounts");
      for (let i = 0; i < 10; ++i) beeperData.acceptLine(JSON.stringify({event: "chatsChanged", data: {}}));
      compare(pending("unreadCounts").length, 1);
      beeperData.respond("unreadCounts", {counts: {Telegram: 2}});
      wait(200); compare(pending("unreadCounts").length, 0, "Passive changes are throttled, not scanned for every event");
    }
    function test_chats_fill_viewport_then_paginate_near_bottom() {
      beeperData.refreshChats(false);
      beeperData.respond("chats", {items: chats(0, 2), oldestCursor: "page-1", hasMore: true});
      compare(waitRequest("chats").params.cursor, "page-1");
      wait(180); compare(pending("chats").length, 1, "One request in flight");
      beeperData.respond("chats", {items: chats(2, 20), oldestCursor: "page-2", hasMore: true});
      wait(250); compare(pending("chats").length, 0);
      panel.chatList.positionViewAtEnd();
      compare(waitRequest("chats").params.cursor, "page-2");
      beeperData.respond("chats", {items: chats(22, 4), hasMore: false});
      panel.chatList.positionViewAtEnd(); wait(250);
      compare(pending("chats").length, 0); compare(beeperData.chats.length, 26);
    }
    function test_network_filter_keeps_paging_until_matching_chats_are_visible() {
      beeperData.networkFilter = "whatsapp";
      beeperData.refreshChats(false);
      beeperData.respond("chats", {items: chats(0, 20), oldestCursor: "page-1", hasMore: true});
      waitRequest("chats"); compare(panel.filteredChats.length, 0);
      beeperData.respond("chats", {items: chats(20, 15, "WhatsApp"), oldestCursor: "page-2", hasMore: true});
      wait(250); compare(pending("chats").length, 0); compare(panel.filteredChats.length, 15);
    }
    function test_sidebar_refresh_does_not_scroll_back_to_the_selected_chat() {
      beeperData.chats = chats(0, 90);
      panel.chooseChat(60);
      beeperData.respond("messages", {items: [], hasMore: false});
      const list = panel.chatList;
      wait(350);
      list.positionViewAtIndex(18, ListView.Beginning); list.forceLayout(); wait(30);
      const first = list.itemAtIndex(list.indexAt(1, list.contentY + 2));
      verify(first !== null);
      const anchor = first.row.id, offset = first.y - list.contentY;
      const before = beeperData.chats;
      beeperData.chats = [{id: "new-chat", title: "New activity", network: "Telegram"}].concat(before);
      wait(350); list.forceLayout();
      compare(beeperData.currentChatID, "chat-60");
      const after = list.itemAtIndex(list.indexAt(1, list.contentY + 2));
      compare(after.row.id, anchor, "A passive refresh must keep the conversation being browsed in view");
      fuzzyCompare(after.y - list.contentY, offset, 0.5);
      const y = list.contentY; wait(250);
      fuzzyCompare(list.contentY, y, 0.5, "No delayed automatic scroll after the refresh");
      const latest = beeperData.chats;
      beeperData.chats = [latest.find(chat => chat.id === "chat-80")].concat(latest.filter(chat => chat.id !== "chat-80"));
      wait(350); list.forceLayout();
      const reordered = list.itemAtIndex(list.indexAt(1, list.contentY + 2));
      compare(reordered.row.id, anchor, "New activity in another chat must not move the reading position");
      fuzzyCompare(reordered.y - list.contentY, offset, 0.5);
    }
    function test_mark_unread_keeps_the_selected_chat_visible_when_the_api_reorders_it() {
      beeperData.chats = chats(0, 80);
      panel.chooseChat(40); beeperData.respond("messages", {items: [], hasMore: false});
      const list = panel.chatList;
      wait(100); list.forceLayout();
      const selected = list.itemAtIndex(40);
      verify(selected !== null && selected.y >= list.contentY && selected.y + selected.height <= list.contentY + list.height + 0.5);
      panel.focusNavigation(); keyClick(Qt.Key_N);
      compare(waitRequest("unread").params.chatID, "chat-40");
      beeperData.respond("unread", {}); waitRequest("chats");
      const updated = Object.assign({}, beeperData.chats[40], {isMarkedUnread: true});
      beeperData.respond("chats", {items: [updated].concat(beeperData.chats.filter(chat => chat.id !== updated.id)), hasMore: false});
      wait(100); list.forceLayout();
      compare(beeperData.currentChatID, "chat-40"); compare(panel.chatIndex, 0);
      const moved = list.itemAtIndex(0);
      verify(moved !== null, "The marked conversation must remain on screen, not just exist in the model");
      verify(moved.y >= list.contentY && moved.y + moved.height <= list.contentY + list.height + 0.5);
      verify(moved.unread);
    }
    function test_sidebar_keyboard_selection_cancels_pending_wheel_motion() {
      beeperData.chats = chats(0, 80);
      panel.chooseChat(0); beeperData.respond("messages", {items: [], hasMore: false});
      const list = panel.chatList;
      list.positionViewAtIndex(20, ListView.Beginning); list.forceLayout(); wait(20);
      mouseWheel(list, list.width / 2, list.height / 2, 0, -120);
      panel.chooseChat(50); list.forceLayout();
      const destination = list.contentY;
      wait(250);
      fuzzyCompare(list.contentY, destination, 0.5);
      const selected = list.itemAtIndex(50);
      verify(selected !== null);
      verify(selected.y >= list.contentY && selected.y + selected.height <= list.contentY + list.height + 0.5);
    }
    function test_sidebar_motion_stops_while_a_dialog_is_open() {
      beeperData.chats = chats(0, 80); wait(20);
      const list = panel.chatList;
      list.positionViewAtIndex(20, ListView.Beginning); list.forceLayout();
      mouseWheel(list, list.width / 2, list.height / 2, 0, -120);
      panel.openModal("help");
      const paused = list.contentY; wait(250);
      fuzzyCompare(list.contentY, paused, 0.5);
      panel.closeModal(); wait(250);
      fuzzyCompare(list.contentY, paused, 0.5);
    }
    function test_failed_or_repeated_chat_cursor_does_not_loop() {
      beeperData.refreshChats(false);
      beeperData.respond("chats", {items: chats(0, 1), oldestCursor: "page-1", hasMore: true});
      waitRequest("chats");
      beeperData.respond("chats", null, {message: "offline"});
      wait(350); compare(pending("chats").length, 0); verify(beeperData.chatsPaginationBlocked);
      beeperData.refreshChats(false);
      beeperData.respond("chats", {items: chats(0, 1), oldestCursor: "page-1", hasMore: true});
      waitRequest("chats");
      beeperData.respond("chats", {items: chats(0, 1), oldestCursor: "page-1", hasMore: true});
      wait(350); compare(pending("chats").length, 0); verify(!beeperData.hasMoreChats);
    }
    function test_history_prepend_preserves_visible_message_and_selection() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(0, ListView.Beginning);
      panel.messageIndex = 1;
      compare(waitRequest("messages").params.cursor, "history-30");
      const anchorID = beeperData.messages[Math.max(0, list.indexAt(1, list.contentY + 12))].id;
      beeperData.respond("messages", {items: messages(0, 30), oldestCursor: "history-0", hasMore: true});
      tryCompare(panel, "restoringView", false); wait(180);
      compare(beeperData.messages[Math.max(0, list.indexAt(1, list.contentY + 12))].id, anchorID);
      compare(beeperData.messages[panel.messageIndex].id, "message-31");
      compare(pending("messages").length, 0); verify(!list.atYEnd);
      const before = beeperData.viewPositions["chat-0"].messageID;
      panel.changeTextSize(2); tryCompare(panel, "restoringView", false); wait(30);
      compare(beeperData.messages[Math.max(0, list.indexAt(1, list.contentY + 12))].id, before);
    }
    function test_short_history_fills_automatically_and_stops_at_end() {
      beeperData.chats = chats(0, 1); beeperData.selectChat("chat-0");
      beeperData.respond("messages", {items: messages(3, 1), oldestCursor: "history-3", hasMore: true});
      compare(waitRequest("messages").params.cursor, "history-3");
      beeperData.respond("messages", {items: messages(0, 3), oldestCursor: "history-0", hasMore: false});
      wait(250); compare(pending("messages").length, 0); verify(!beeperData.hasOlderMessages);
    }
    function test_hidden_panel_does_not_page_and_stale_chat_responses_are_ignored() {
      panel.active = false;
      beeperData.refreshChats(false);
      beeperData.respond("chats", {items: chats(0, 2), oldestCursor: "page-1", hasMore: true});
      wait(250); compare(pending("chats").length, 0);
      panel.active = true; waitRequest("chats");
      beeperData.selectChat("chat-0"); beeperData.selectChat("chat-1");
      beeperData.respond("messages", {items: messages(0, 3), oldestCursor: "stale", hasMore: true});
      compare(beeperData.messages.length, 0); compare(beeperData.currentChatID, "chat-1");
      beeperData.respond("messages", {items: [], hasMore: false});
      wait(250); compare(pending("messages").length, 0);
    }
    function test_history_failure_and_nonadvancing_cursor_stop_automatic_retries() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(0, ListView.Beginning); waitRequest("messages");
      beeperData.respond("messages", null, {message: "offline"});
      wait(350); compare(pending("messages").length, 0); verify(beeperData.messagesPaginationBlocked);
      beeperData.loadMessages(false);
      beeperData.respond("messages", {items: messages(30, 30), oldestCursor: "history-30", hasMore: true});
      waitRequest("messages");
      beeperData.respond("messages", {items: messages(30, 1), oldestCursor: "history-30", hasMore: true});
      wait(350); compare(pending("messages").length, 0); verify(!beeperData.hasOlderMessages);
    }
    function test_sending_from_history_returns_to_end_after_refresh() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(8, ListView.Beginning); panel.updateView();
      verify(!list.atYEnd);
      beeperData.draftText = "Sent while reading history";
      beeperData.sendMessage(); compare(pending("read").length, 0);
      beeperData.respond("send", {pendingMessageID: "sent"});
      compare(waitRequest("read").params.chatID, "chat-0");
      compare(pending("read")[0].params.messageID, "message-59");
      tryVerify(() => list.atYEnd);
      waitRequest("messages");
      beeperData.respond("messages", {items: messages(60, 1), hasMore: false});
      tryCompare(panel, "restoringView", false); wait(30);
      verify(list.atYEnd); verify(beeperData.viewAtLatest);
      compare(beeperData.draftText, "");
    }
    function test_send_during_older_page_keeps_end_through_both_responses() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(0, ListView.Beginning); waitRequest("messages");
      beeperData.draftText = "Send during pagination";
      beeperData.sendMessage(); beeperData.respond("send", {});
      tryVerify(() => list.atYEnd); verify(beeperData.trailingMessagesRefresh);
      beeperData.respond("messages", {items: messages(0, 30), oldestCursor: "history-0", hasMore: false});
      waitRequest("messages");
      beeperData.respond("messages", {items: messages(60, 1), hasMore: false});
      tryCompare(panel, "restoringView", false); wait(30);
      verify(list.atYEnd);
    }
    function test_sent_reply_stays_at_end_when_original_arrives_later() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(8, ListView.Beginning);
      beeperData.replyToMessageID = "remote-original";
      beeperData.draftText = "Reply from history"; beeperData.sendMessage();
      compare(waitRequest("send").params.replyToMessageID, "remote-original");
      beeperData.respond("send", {});
      waitRequest("messages");
      beeperData.respond("messages", {items: [Object.assign(messages(60, 1)[0], {isSender: true, linkedMessageID: "remote-original"})], hasMore: false});
      tryCompare(panel, "restoringView", false); wait(30);
      verify(list.atYEnd);
      waitRequest("message");
      beeperData.respond("message", {id: "remote-original", chatID: "chat-0", senderName: "Camille", text: "An original long enough to need several lines in the quote. ".repeat(10)});
      wait(50);
      verify(list.atYEnd, "Resolving the quote must keep the just-sent reply visible");
      verify(panel.pinLatest);
      mouseWheel(list, list.width / 2, list.height / 2, 0, 120, Qt.NoButton, Qt.NoModifier);
      verify(!panel.pinLatest, "Ordinary scrolling releases the send anchor");
      panel.pinLatest = true; panel.focusNavigation(); panel.navigation = "messages";
      keyClick(Qt.Key_K, Qt.ControlModifier); verify(!panel.pinLatest, "Message navigation also releases the anchor");
    }
    function test_failed_send_does_not_move_reader_or_clear_draft() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(8, ListView.Beginning); panel.updateView();
      const position = list.contentY;
      beeperData.draftText = "Keep on failure"; beeperData.sendMessage();
      beeperData.respond("send", null, {message: "not sent"}); wait(50);
      compare(list.contentY, position); compare(beeperData.draftText, "Keep on failure");
      compare(pending("read").length, 0, "An unsuccessful reply must not mark the chat read");
    }
    function test_late_send_success_never_scrolls_another_chat() {
      seedHistory();
      beeperData.chats = chats(0, 2);
      beeperData.draftText = "Old chat send"; beeperData.sendMessage();
      beeperData.selectChat("chat-1");
      beeperData.respond("messages", {items: messages(0, 30).map(row => Object.assign({}, row, {chatID: "chat-1"})), hasMore: false});
      tryCompare(panel, "restoringView", false); wait(20);
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(8, ListView.Beginning); panel.updateView();
      const position = list.contentY;
      beeperData.respond("send", {}); wait(50);
      compare(waitRequest("read").params.chatID, "chat-0");
      compare(pending("read")[0].params.messageID, "message-59");
      compare(list.contentY, position); compare(beeperData.currentChatID, "chat-1");
      verify(beeperData.viewPositions["chat-0"].atLatest);
      compare(pending("messages").length, 0);
    }
    function test_reply_keeps_read_boundary_from_before_new_incoming_message() {
      seedHistory();
      beeperData.draftText = "Reply in flight"; beeperData.sendMessage();
      beeperData.loadMessages(false);
      beeperData.respond("messages", {items: messages(60, 1), hasMore: false});
      beeperData.respond("send", {});
      compare(waitRequest("read").params.messageID, "message-59", "The new message must remain unread");
      beeperData.respond("read", {});
      beeperData.markChatRead(beeperData.currentChatID);
      compare(waitRequest("read").params.chatID, "chat-0");
      verify(!pending("read")[0].params.messageID, "Manual marking covers the entire conversation");
    }
    function test_refresh_does_not_destroy_visible_delegates_or_cancel_inertia() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(15, ListView.Beginning); list.forceLayout();
      const item = list.itemAtIndex(15);
      verify(item !== null);
      list.flick(0, 800); wait(20); verify(list.flicking);
      beeperData.loadMessages(false);
      beeperData.respond("messages", {items: messages(30, 31), hasMore: false});
      wait(20);
      compare(list.itemAtIndex(15), item, "Unchanged messages keep the same QML delegate");
      verify(list.flicking, "A background snapshot must not stop a user scroll");
      list.cancelFlick();
    }
    function test_pagination_is_not_starved_by_continuous_scroll_events() {
      beeperData.refreshChats(false);
      beeperData.respond("chats", {items: chats(0, 2), oldestCursor: "page-1", hasMore: true});
      for (let i = 0; i < 12; ++i) { panel.schedulePagination(); wait(20); }
      compare(pending("chats").length, 1, "Fetch during the gesture, not only after its end");
    }
    function test_vim_half_page_uses_native_animation_and_mouse_drag_does_not_scroll() {
      seedHistory();
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(15, ListView.Beginning); list.forceLayout();
      const before = list.contentY;
      panel.focusNavigation(); panel.navigation = "messages";
      keyClick(Qt.Key_D, Qt.ControlModifier); wait(20);
      verify(list.moving); tryCompare(list, "moving", false, 2000);
      fuzzyCompare(list.contentY, before + list.height / 2, 2);
      keyClick(Qt.Key_U, Qt.ControlModifier);
      tryCompare(list, "moving", false, 2000);
      fuzzyCompare(list.contentY, before, 2);
      compare(list.acceptedButtons, Qt.NoButton);
      mouseDrag(list, list.width / 2, list.height / 2, 0, -100);
      fuzzyCompare(list.contentY, before, 2);
    }
    function test_mixed_heights_do_not_resize_the_scrollbar_when_scrolling() {
      beeperData.chats = chats(0, 1); beeperData.selectChat("chat-0");
      const batch = messages(0, 200).map((row, index) => Object.assign(row, index % 3 === 0
        ? {text: "A long message\n".repeat(8)} : index % 3 === 1 ? {attachments: [{type: "img"}]} : {}));
      beeperData.respond("messages", {items: batch, hasMore: false});
      tryCompare(panel, "restoringView", false); wait(60);
      const list = findChild(panel, "beeperMessages"), bar = findChild(panel, "beeperHistoryScrollBar");
      list.forceLayout();
      const extent = list.contentHeight, size = bar.size;
      for (const index of [0, 10, 70, 110, 170, 199]) {
        list.positionViewAtIndex(index, ListView.Beginning); wait(20);
        fuzzyCompare(list.contentHeight, extent, 0.1);
        fuzzyCompare(bar.size, size, 0.00001);
      }
      let activeMedia = 0;
      for (let i = 0; i < list.count; ++i) if (list.itemAtIndex(i).renderMedia) ++activeMedia;
      verify(activeMedia < 20, "Offscreen avatars and media must remain lazy");
    }
    function test_bubbles_have_twelve_pixel_gaps_and_metadata_inside() {
      seedHistory();
      const list = findChild(panel, "beeperMessages"); list.forceLayout();
      const first = list.itemAtIndex(0), second = list.itemAtIndex(1);
      const firstBubble = findChild(first, "beeperMessageBubble"), secondBubble = findChild(second, "beeperMessageBubble");
      const gap = second.y + secondBubble.mapToItem(second, 0, 0).y
        - first.y - firstBubble.mapToItem(first, 0, 0).y - firstBubble.height;
      fuzzyCompare(gap, 12, 0.1);
      const meta = findChild(first, "beeperMessageMeta"), pos = meta.mapToItem(firstBubble, 0, 0);
      verify(pos.y >= 0 && pos.y + meta.height <= firstBubble.height);
    }
  }
}
