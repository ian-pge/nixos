import QtQuick
import QtTest
import Quickshell

// Low Priority requests go only to the in-memory transport, never to real accounts.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  Window { id: window; width: 1280; height: 900; visible: true }
  SignalSpy { id: closeSpy; target: fixture.panel; signalName: "closeRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperLowPriority"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function pending(method) { return beeperData.requests.filter(request => request.method === method); }
    function request(method) { tryVerify(() => pending(method).length > 0, 1500); return pending(method)[0]; }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true});
      beeperData.chats = [
        {id: "current", title: "Current", network: "Telegram", unreadCount: 3},
        {id: "next", title: "Next", network: "Telegram"},
        {id: "tg-priority", title: "Older Telegram", network: "Telegram", isLowPriority: true},
        {id: "wa-priority", title: "Older WhatsApp", network: "WhatsApp", isLowPriority: true}
      ];
      beeperData.networkFilter = "telegram"; panel.chooseChat(0);
      beeperData.respond("messages", {items: [{id: "m1", chatID: "current", text: "Message"}], hasMore: false});
      tryCompare(panel, "restoringView", false); panel.focusNavigation(); closeSpy.clear(); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperLowPriority: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_a_switches_between_inbox_and_only_low_priority_in_the_current_network() {
      compare(panel.filteredChats.length, 2);
      beeperData.draftText = "Inbox draft";
      keyClick(Qt.Key_A); verify(panel.showLowPriority); compare(panel.filteredChats.length, 1);
      verify(panel.filteredChats.some(chat => chat.id === "tg-priority"));
      verify(panel.filteredChats.every(chat => chat.isLowPriority === true));
      verify(!panel.filteredChats.some(chat => chat.id === "wa-priority"));
      verify(findChild(panel, "beeperLowPriorityViewIndicator").visible);
      compare(pending("updateChat").length, 0, "Viewing Low Priority never modifies Beeper");
      compare(beeperData.currentChatID, "tg-priority"); compare(beeperData.localDrafts.current.text, "Inbox draft");
      compare(pending("read").length, 0); compare(pending("unread").length, 0);
      keyClick(Qt.Key_A); verify(!panel.showLowPriority); compare(panel.filteredChats.length, 2);
      compare(beeperData.currentChatID, "current");
      verify(!findChild(panel, "beeperLowPriorityViewIndicator").visible);
      keyClick(Qt.Key_A);
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "whatsapp");
      compare(panel.filteredChats.length, 1); compare(panel.filteredChats[0].id, "wa-priority");
      keyClick(Qt.Key_A); verify(!panel.showLowPriority); compare(panel.filteredChats.length, 0);
      compare(beeperData.currentChatID, "");
    }
    function test_shift_a_low_priority_after_success_and_preserves_draft_and_unread() {
      beeperData.draftText = "Keep this draft";
      keyClick(Qt.Key_A, Qt.ShiftModifier);
      const operation = request("updateChat"); compare(operation.params.chatID, "current"); compare(operation.params.changes.isLowPriority, true);
      verify(!beeperData.currentChat.isLowPriority); compare(beeperData.currentChatID, "current");
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(pending("updateChat").length, 1);
      beeperData.respond("updateChat", {});
      compare(beeperData.currentChatID, "next");
      const lowPriority = beeperData.chats.find(chat => chat.id === "current"); verify(lowPriority.isLowPriority); compare(lowPriority.unreadCount, 3);
      compare(beeperData.localDrafts.current.text, "Keep this draft");
      compare(pending("read").length, 0); compare(pending("unread").length, 0);
      verify(!panel.filteredChats.some(chat => chat.id === "current"));
      keyClick(Qt.Key_A); verify(panel.filteredChats.some(chat => chat.id === "current"));
    }
    function test_shift_a_restores_an_lowPriority_conversation_without_losing_its_network() {
      keyClick(Qt.Key_A); panel.chooseChat(panel.filteredChats.findIndex(chat => chat.id === "tg-priority"));
      beeperData.respond("messages", {items: [], hasMore: false}); panel.focusNavigation();
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(request("updateChat").params.changes.isLowPriority, false);
      beeperData.respond("updateChat", {});
      compare(beeperData.currentChatID, ""); compare(panel.filteredChats.length, 0);
      verify(panel.showLowPriority); compare(panel.networkFilter, "telegram");
      verify(!beeperData.chats.find(chat => chat.id === "tg-priority").isLowPriority);
      keyClick(Qt.Key_A); verify(!panel.showLowPriority);
      verify(panel.filteredChats.some(chat => chat.id === "tg-priority"));
      compare(beeperData.currentChat.network, "Telegram");
      compare(pending("read").length, 0);
    }
    function test_restoring_moves_to_the_next_priority_without_showing_inbox_chats() {
      beeperData.chats = beeperData.chats.concat([{id: "tg-other", title: "Another priority", network: "Telegram", isLowPriority: true}]);
      keyClick(Qt.Key_A); compare(beeperData.currentChatID, "tg-priority");
      beeperData.respond("messages", {items: [], hasMore: false});
      beeperData.draftText = "Priority draft";
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat"); beeperData.respond("updateChat", {});
      verify(panel.showLowPriority); compare(beeperData.currentChatID, "tg-other");
      compare(panel.filteredChats.length, 1); verify(panel.filteredChats.every(chat => chat.isLowPriority));
      compare(beeperData.localDrafts["tg-priority"].text, "Priority draft");
    }
    function test_explicit_chat_targets_select_the_view_that_contains_them() {
      keyClick(Qt.Key_A); verify(panel.showLowPriority);
      beeperData.selectChat("current"); verify(!panel.showLowPriority);
      compare(beeperData.currentChatID, "current"); verify(panel.filteredChats.some(chat => chat.id === "current"));
      beeperData.selectChat("tg-priority"); verify(panel.showLowPriority);
      compare(panel.filteredChats.length, 1); compare(beeperData.currentChatID, "tg-priority");
      compare(pending("read").length, 0);
    }
    function test_priority_view_loads_past_inbox_only_pages() {
      beeperData.chats = beeperData.chats.filter(chat => !chat.isLowPriority);
      beeperData.chatsInitialized = true; beeperData.hasMoreChats = true; beeperData.chatsCursor = "first";
      keyClick(Qt.Key_A); verify(panel.showLowPriority); compare(panel.filteredChats.length, 0);
      compare(beeperData.currentChatID, ""); compare(request("chats").params.cursor, "first");
      beeperData.respond("chats", {items: [{id: "older-inbox", network: "Telegram"}], hasMore: true, oldestCursor: "second"});
      compare(panel.filteredChats.length, 0); compare(request("chats").params.cursor, "second");
      beeperData.respond("chats", {items: [{id: "older-priority", network: "Telegram", isLowPriority: true}], hasMore: false});
      tryCompare(beeperData, "currentChatID", "older-priority"); compare(panel.filteredChats.length, 1);
      verify(panel.showLowPriority); compare(pending("read").length, 0);
    }
    function test_failure_and_late_response_do_not_priority_the_wrong_chat() {
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat");
      beeperData.respond("updateChat", null, {message: "Failed"});
      verify(!beeperData.currentChat.isLowPriority); compare(beeperData.currentChatID, "current");
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat");
      panel.chooseChat(1); beeperData.respond("messages", {items: [], hasMore: false});
      beeperData.respond("updateChat", {});
      compare(beeperData.currentChatID, "next"); verify(!beeperData.currentChat.isLowPriority);
      verify(beeperData.chats.find(chat => chat.id === "current").isLowPriority);
    }
    function test_old_list_response_cannot_undo_a_confirmed_priority() {
      const oldRows = beeperData.chats;
      beeperData.refreshChats(false); request("chats");
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat"); beeperData.respond("updateChat", {});
      beeperData.respond("chats", {items: oldRows, hasMore: false});
      verify(beeperData.chats.find(chat => chat.id === "current").isLowPriority);
      verify(!panel.filteredChats.some(chat => chat.id === "current"));
    }
    function test_native_priority_survives_messages_and_follows_other_clients() {
      const original = beeperData.chats;
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat"); beeperData.respond("updateChat", {});
      request("chats");
      beeperData.respond("chats", {items: original.map(chat => chat.id === "current"
        ? Object.assign({}, chat, {isLowPriority: true, isMarkedUnread: true, unreadCount: 10,
          preview: {id: "new-message", text: "New activity"}}) : chat), hasMore: false});
      const lowPriority = beeperData.chats.find(chat => chat.id === "current");
      verify(lowPriority.isLowPriority); verify(lowPriority.isMarkedUnread); compare(lowPriority.unreadCount, 10);
      compare(lowPriority.preview.id, "new-message");
      verify(!panel.filteredChats.some(chat => chat.id === "current"));
      // A later edit in another client must override the earlier local action.
      beeperData.refreshChats(false); request("chats");
      beeperData.respond("chats", {items: original, hasMore: false});
      verify(panel.filteredChats.some(chat => chat.id === "current"));
      verify(!beeperData.chats.find(chat => chat.id === "current").isLowPriority);
      compare(pending("updateChat").length, 0);
      compare(pending("read").length, 0);
    }
    function test_remote_priority_change_moves_selection_and_preserves_drafts() {
      const original = beeperData.chats;
      beeperData.draftText = "Keep my draft";
      beeperData.refreshChats(false); request("chats");
      beeperData.respond("chats", {items: original.map(chat => chat.id === "current"
        ? Object.assign({}, chat, {isLowPriority: true}) : chat), hasMore: false});
      tryCompare(beeperData, "currentChatID", "next");
      compare(beeperData.localDrafts.current.text, "Keep my draft");
      compare(pending("updateChat").length, 0); compare(pending("read").length, 0);
      keyClick(Qt.Key_A); panel.chooseChat(panel.filteredChats.findIndex(chat => chat.id === "current"));
      beeperData.refreshChats(false); request("chats");
      beeperData.respond("chats", {items: original, hasMore: false});
      tryCompare(beeperData, "currentChatID", "tg-priority");
      verify(panel.showLowPriority);
    }
    function test_old_snapshot_cannot_confirm_a_newer_reversed_priority_operation() {
      const original = beeperData.chats;
      beeperData.refreshChats(false); request("chats");
      beeperData.setChatLowPriority("current", true); beeperData.respond("updateChat", {});
      beeperData.setChatLowPriority("current", false); beeperData.respond("updateChat", {});
      // This snapshot agrees with the restore, but predates both operations.
      beeperData.respond("chats", {items: original.map(chat => chat.id === "current"
        ? Object.assign({}, chat, {isLowPriority: true}) : chat), hasMore: false});
      verify(!beeperData.chats.find(chat => chat.id === "current").isLowPriority);
      request("chats");
      beeperData.respond("chats", {items: original, hasMore: false});
      verify(panel.filteredChats.some(chat => chat.id === "current"));
      compare(pending("updateChat").length, 0);
    }
    function test_priority_finishing_while_closed_reconciles_selection_on_reopening() {
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat"); panel.active = false;
      beeperData.respond("updateChat", {}); verify(beeperData.currentChat.isLowPriority);
      panel.active = true; compare(beeperData.currentChatID, "next"); verify(!panel.showLowPriority);
      beeperData.respond("messages", {items: [], hasMore: false});
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat"); panel.active = false;
      beeperData.respond("updateChat", {});
      panel.active = true; compare(beeperData.currentChatID, ""); compare(panel.filteredChats.length, 0);
    }
    function test_restore_finishing_while_closed_reconciles_the_priority_view_on_reopening() {
      keyClick(Qt.Key_A); beeperData.respond("messages", {items: [], hasMore: false});
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat"); panel.active = false;
      beeperData.respond("updateChat", {}); verify(!beeperData.currentChat.isLowPriority);
      panel.active = true; verify(panel.showLowPriority);
      compare(beeperData.currentChatID, ""); compare(panel.filteredChats.length, 0);
    }
    function test_typing_modals_search_and_recording_do_not_trigger_priority_shortcuts() {
      panel.compose(); keyClick(Qt.Key_A); keyClick(Qt.Key_A, Qt.ShiftModifier);
      verify(panel.composer.text.toLowerCase() === "aa"); verify(!panel.showLowPriority); compare(pending("updateChat").length, 0);
      panel.focusNavigation(); panel.openChatSearch(); wait(0);
      keyClick(Qt.Key_A); verify(panel.searchField.text.toLowerCase() === "a"); verify(!panel.showLowPriority);
      keyClick(Qt.Key_Escape); panel.openModal("help"); wait(0);
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(pending("updateChat").length, 0);
      panel.closeModal(); panel.preparingRecording = true;
      keyClick(Qt.Key_A); keyClick(Qt.Key_A, Qt.ShiftModifier); verify(!panel.showLowPriority); compare(pending("updateChat").length, 0);
      panel.preparingRecording = false; panel.openConversationSearch(); wait(0);
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(pending("updateChat").length, 0);
      keyClick(Qt.Key_Escape); panel.windowFocused = false;
      keyClick(Qt.Key_A); keyClick(Qt.Key_A, Qt.ShiftModifier); verify(!panel.showLowPriority); compare(pending("updateChat").length, 0);
    }
    function test_priority_support_is_decided_by_beeper_even_for_read_only_chats() {
      beeperData.chats = beeperData.chats.map(chat => chat.id === "current" ? Object.assign({}, chat, {isReadOnly: true}) : chat);
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(request("updateChat").params.changes.isLowPriority, true);
      beeperData.respond("updateChat", null, {message: "Not supported by this account"});
      verify(!beeperData.currentChat.isLowPriority);
      compare(beeperData.currentChatID, "current");
    }
    function test_native_update_response_supplies_the_actual_priority_and_mute_state() {
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat");
      beeperData.respond("updateChat", {id: "current", isLowPriority: true, isMuted: true});
      const chat = beeperData.chats.find(chat => chat.id === "current");
      verify(chat.isLowPriority); verify(chat.isMuted); compare(chat.unreadCount, 3);
    }
    function test_legacy_archive_flag_does_not_control_the_priority_views() {
      beeperData.chats = beeperData.chats.map(chat => chat.id === "current"
        ? Object.assign({}, chat, {isArchived: true}) : chat);
      verify(panel.filteredChats.some(chat => chat.id === "current"));
      keyClick(Qt.Key_A);
      verify(!panel.filteredChats.some(chat => chat.id === "current"));
    }
    function test_counter_counts_only_lowPriority_unread_chats_in_the_priority_view() {
      // The dedicated priority counter includes lowPriority manual unread markers.
      request("unreadCounts"); beeperData.respond("unreadCounts", {
        counts: {Telegram: 2, WhatsApp: 1}, allCounts: {Telegram: 6, WhatsApp: 3}, lowPriorityCounts: {Telegram: 4, WhatsApp: 2}
      });
      const counter = findChild(panel, "beeperUnreadConversationCount");
      compare(counter.text, "2 unread"); keyClick(Qt.Key_A); compare(counter.text, "4 unread");
      keyClick(Qt.Key_Tab); compare(counter.text, "2 unread");
      keyClick(Qt.Key_A); compare(counter.text, "1 unread");
    }
    function test_older_backend_does_not_show_an_inclusive_or_fabricated_priority_count() {
      request("unreadCounts"); beeperData.respond("unreadCounts", {counts: {Telegram: 1}, allCounts: {Telegram: 5}});
      keyClick(Qt.Key_A); verify(!beeperData.unreadCountsReady);
      compare(findChild(panel, "beeperUnreadConversationCount").text, "— unread");
      keyClick(Qt.Key_A); verify(beeperData.unreadCountsReady);
      compare(findChild(panel, "beeperUnreadConversationCount").text, "1 unread");
    }
    function test_no_lowPriority_unread_conversations_is_a_ready_zero() {
      request("unreadCounts"); beeperData.respond("unreadCounts", {counts: {Telegram: 1}, lowPriorityCounts: {}});
      keyClick(Qt.Key_A); verify(beeperData.unreadCountsReady);
      compare(findChild(panel, "beeperUnreadConversationCount").text, "0 unread");
    }
    function test_demo_counter_matches_the_priority_only_filter() {
      beeperData.demo = true;
      beeperData.chats = beeperData.chats.map(chat => chat.id === "tg-priority" ? Object.assign({}, chat, {isMarkedUnread: true}) : chat);
      compare(beeperData.unreadConversationCount("telegram"), 1);
      keyClick(Qt.Key_A); compare(panel.filteredChats.length, 1);
      compare(beeperData.unreadConversationCount("telegram"), 1);
    }
    function test_manual_unread_markers_and_escape_do_not_reopen_low_priority() {
      beeperData.chats = beeperData.chats.map(chat => chat.id === "tg-priority" ? Object.assign({}, chat, {isMarkedUnread: true}) : chat);
      verify(!panel.filteredChats.some(chat => chat.id === "tg-priority"));
      keyClick(Qt.Key_A); verify(panel.showLowPriority); compare(panel.filteredChats.length, 1);
      verify(panel.filteredChats.every(chat => chat.isLowPriority));
      keyClick(Qt.Key_N); request("unread");
      beeperData.respond("unread", {id: "tg-priority", isMarkedUnread: true});
      verify(beeperData.currentChat.isLowPriority); verify(panel.showLowPriority);
      keyClick(Qt.Key_Escape); verify(!panel.showLowPriority); compare(closeSpy.count, 0);
      verify(!panel.filteredChats.some(chat => chat.id === "tg-priority"));
      compare(pending("updateChat").length, 0);
    }
    function test_moving_a_manual_unread_reminder_preserves_its_read_state() {
      beeperData.applyReadState("current", {id: "current", isMarkedUnread: true, unreadCount: 0});
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("updateChat"); beeperData.respond("updateChat", {});
      const chat = beeperData.chats.find(chat => chat.id === "current");
      verify(chat.isLowPriority); verify(chat.isMarkedUnread); compare(chat.unreadCount, 0);
      compare(beeperData.currentChatID, "next");
      verify(!panel.filteredChats.some(chat => chat.id === "current"));
      compare(pending("read").length, 0); compare(pending("unread").length, 0);
      panel.openChat("current", "");
      verify(panel.showLowPriority); verify(beeperData.currentChat.isLowPriority);
      compare(pending("updateChat").length, 0, "Opening a notification target must not restore the chat");
    }
  }
}
