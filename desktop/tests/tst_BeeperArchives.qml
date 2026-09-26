import QtQuick
import QtTest
import Quickshell

// Archive requests go only to the in-memory transport, never to real accounts.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  Window { id: window; width: 1280; height: 900; visible: true }
  SignalSpy { id: closeSpy; target: fixture.panel; signalName: "closeRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperArchives"
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
        {id: "tg-archive", title: "Older Telegram", network: "Telegram", isArchived: true},
        {id: "wa-archive", title: "Older WhatsApp", network: "WhatsApp", isArchived: true}
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
      console.log("BeeperArchives: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_a_switches_between_inbox_and_only_archives_in_the_current_network() {
      compare(panel.filteredChats.length, 2);
      beeperData.draftText = "Inbox draft";
      keyClick(Qt.Key_A); verify(panel.showArchived); compare(panel.filteredChats.length, 1);
      verify(panel.filteredChats.some(chat => chat.id === "tg-archive"));
      verify(panel.filteredChats.every(chat => chat.isArchived === true));
      verify(!panel.filteredChats.some(chat => chat.id === "wa-archive"));
      verify(findChild(panel, "beeperArchiveViewIndicator").visible);
      compare(pending("archive").length, 0, "Viewing archives never modifies Beeper");
      compare(beeperData.currentChatID, "tg-archive"); compare(beeperData.localDrafts.current.text, "Inbox draft");
      compare(pending("read").length, 0); compare(pending("unread").length, 0);
      keyClick(Qt.Key_A); verify(!panel.showArchived); compare(panel.filteredChats.length, 2);
      compare(beeperData.currentChatID, "current");
      verify(!findChild(panel, "beeperArchiveViewIndicator").visible);
      keyClick(Qt.Key_A);
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "whatsapp");
      compare(panel.filteredChats.length, 1); compare(panel.filteredChats[0].id, "wa-archive");
      keyClick(Qt.Key_A); verify(!panel.showArchived); compare(panel.filteredChats.length, 0);
      compare(beeperData.currentChatID, "");
    }
    function test_shift_a_archives_after_success_and_preserves_draft_and_unread() {
      beeperData.draftText = "Keep this draft";
      keyClick(Qt.Key_A, Qt.ShiftModifier);
      const operation = request("archive"); compare(operation.params.chatID, "current"); compare(operation.params.archived, true);
      verify(!beeperData.currentChat.isArchived); compare(beeperData.currentChatID, "current");
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(pending("archive").length, 1);
      beeperData.respond("archive", {});
      compare(beeperData.currentChatID, "next");
      const archived = beeperData.chats.find(chat => chat.id === "current"); verify(archived.isArchived); compare(archived.unreadCount, 3);
      compare(beeperData.localDrafts.current.text, "Keep this draft");
      compare(pending("read").length, 0); compare(pending("unread").length, 0);
      verify(!panel.filteredChats.some(chat => chat.id === "current"));
      keyClick(Qt.Key_A); verify(panel.filteredChats.some(chat => chat.id === "current"));
    }
    function test_shift_a_restores_an_archived_conversation_without_losing_its_network() {
      keyClick(Qt.Key_A); panel.chooseChat(panel.filteredChats.findIndex(chat => chat.id === "tg-archive"));
      beeperData.respond("messages", {items: [], hasMore: false}); panel.focusNavigation();
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(request("archive").params.archived, false);
      beeperData.respond("archive", {});
      compare(beeperData.currentChatID, ""); compare(panel.filteredChats.length, 0);
      verify(panel.showArchived); compare(panel.networkFilter, "telegram");
      verify(!beeperData.chats.find(chat => chat.id === "tg-archive").isArchived);
      keyClick(Qt.Key_A); verify(!panel.showArchived);
      verify(panel.filteredChats.some(chat => chat.id === "tg-archive"));
      compare(beeperData.currentChat.network, "Telegram");
      compare(pending("read").length, 0);
    }
    function test_restoring_moves_to_the_next_archive_without_showing_inbox_chats() {
      beeperData.chats = beeperData.chats.concat([{id: "tg-other", title: "Another archive", network: "Telegram", isArchived: true}]);
      keyClick(Qt.Key_A); compare(beeperData.currentChatID, "tg-archive");
      beeperData.respond("messages", {items: [], hasMore: false});
      beeperData.draftText = "Archive draft";
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("archive"); beeperData.respond("archive", {});
      verify(panel.showArchived); compare(beeperData.currentChatID, "tg-other");
      compare(panel.filteredChats.length, 1); verify(panel.filteredChats.every(chat => chat.isArchived));
      compare(beeperData.localDrafts["tg-archive"].text, "Archive draft");
    }
    function test_explicit_chat_targets_select_the_view_that_contains_them() {
      keyClick(Qt.Key_A); verify(panel.showArchived);
      beeperData.selectChat("current"); verify(!panel.showArchived);
      compare(beeperData.currentChatID, "current"); verify(panel.filteredChats.some(chat => chat.id === "current"));
      beeperData.selectChat("tg-archive"); verify(panel.showArchived);
      compare(panel.filteredChats.length, 1); compare(beeperData.currentChatID, "tg-archive");
      compare(pending("read").length, 0);
    }
    function test_archive_view_loads_past_inbox_only_pages() {
      beeperData.chats = beeperData.chats.filter(chat => !chat.isArchived);
      beeperData.chatsInitialized = true; beeperData.hasMoreChats = true; beeperData.chatsCursor = "first";
      keyClick(Qt.Key_A); verify(panel.showArchived); compare(panel.filteredChats.length, 0);
      compare(beeperData.currentChatID, ""); compare(request("chats").params.cursor, "first");
      beeperData.respond("chats", {items: [{id: "older-inbox", network: "Telegram"}], hasMore: true, oldestCursor: "second"});
      compare(panel.filteredChats.length, 0); compare(request("chats").params.cursor, "second");
      beeperData.respond("chats", {items: [{id: "older-archive", network: "Telegram", isArchived: true}], hasMore: false});
      tryCompare(beeperData, "currentChatID", "older-archive"); compare(panel.filteredChats.length, 1);
      verify(panel.showArchived); compare(pending("read").length, 0);
    }
    function test_failure_and_late_response_do_not_archive_the_wrong_chat() {
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("archive");
      beeperData.respond("archive", null, {message: "Failed"});
      verify(!beeperData.currentChat.isArchived); compare(beeperData.currentChatID, "current");
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("archive");
      panel.chooseChat(1); beeperData.respond("messages", {items: [], hasMore: false});
      beeperData.respond("archive", {});
      compare(beeperData.currentChatID, "next"); verify(!beeperData.currentChat.isArchived);
      verify(beeperData.chats.find(chat => chat.id === "current").isArchived);
    }
    function test_old_list_response_cannot_undo_a_confirmed_archive() {
      const oldRows = beeperData.chats;
      beeperData.refreshChats(false); request("chats");
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("archive"); beeperData.respond("archive", {});
      beeperData.respond("chats", {items: oldRows, hasMore: false});
      verify(beeperData.chats.find(chat => chat.id === "current").isArchived);
      verify(!panel.filteredChats.some(chat => chat.id === "current"));
    }
    function test_archive_finishing_while_closed_reconciles_selection_on_reopening() {
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("archive"); panel.active = false;
      beeperData.respond("archive", {}); verify(beeperData.currentChat.isArchived);
      panel.active = true; compare(beeperData.currentChatID, "next"); verify(!panel.showArchived);
      beeperData.respond("messages", {items: [], hasMore: false});
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("archive"); panel.active = false;
      beeperData.respond("archive", {});
      panel.active = true; compare(beeperData.currentChatID, ""); compare(panel.filteredChats.length, 0);
    }
    function test_restore_finishing_while_closed_reconciles_the_archive_view_on_reopening() {
      keyClick(Qt.Key_A); beeperData.respond("messages", {items: [], hasMore: false});
      keyClick(Qt.Key_A, Qt.ShiftModifier); request("archive"); panel.active = false;
      beeperData.respond("archive", {}); verify(!beeperData.currentChat.isArchived);
      panel.active = true; verify(panel.showArchived);
      compare(beeperData.currentChatID, ""); compare(panel.filteredChats.length, 0);
    }
    function test_typing_modals_search_and_recording_do_not_trigger_archive_shortcuts() {
      panel.compose(); keyClick(Qt.Key_A); keyClick(Qt.Key_A, Qt.ShiftModifier);
      verify(panel.composer.text.toLowerCase() === "aa"); verify(!panel.showArchived); compare(pending("archive").length, 0);
      panel.focusNavigation(); panel.openChatSearch(); wait(0);
      keyClick(Qt.Key_A); verify(panel.searchField.text.toLowerCase() === "a"); verify(!panel.showArchived);
      keyClick(Qt.Key_Escape); panel.openModal("help"); wait(0);
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(pending("archive").length, 0);
      panel.closeModal(); panel.preparingRecording = true;
      keyClick(Qt.Key_A); keyClick(Qt.Key_A, Qt.ShiftModifier); verify(!panel.showArchived); compare(pending("archive").length, 0);
      panel.preparingRecording = false; panel.openConversationSearch(); wait(0);
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(pending("archive").length, 0);
      keyClick(Qt.Key_Escape); panel.windowFocused = false;
      keyClick(Qt.Key_A); keyClick(Qt.Key_A, Qt.ShiftModifier); verify(!panel.showArchived); compare(pending("archive").length, 0);
    }
    function test_archive_capability_and_read_only_conversations() {
      beeperData.chats = beeperData.chats.map(chat => chat.id === "current" ? Object.assign({}, chat, {capabilities: {archive: false}}) : chat);
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(pending("archive").length, 0);
      beeperData.chats = beeperData.chats.map(chat => chat.id === "current" ? Object.assign({}, chat, {capabilities: {archive: true}, isReadOnly: true}) : chat);
      keyClick(Qt.Key_A, Qt.ShiftModifier); compare(request("archive").params.archived, true);
    }
    function test_counter_counts_only_archived_unread_chats_in_the_archive_view() {
      // Manual unread archives belong to both sets, so all minus inbox is wrong.
      request("unreadCounts"); beeperData.respond("unreadCounts", {
        counts: {Telegram: 2, WhatsApp: 1}, allCounts: {Telegram: 5, WhatsApp: 3}, archivedCounts: {Telegram: 4, WhatsApp: 2}
      });
      const counter = findChild(panel, "beeperUnreadConversationCount");
      compare(counter.text, "2 unread"); keyClick(Qt.Key_A); compare(counter.text, "4 unread");
      keyClick(Qt.Key_Tab); compare(counter.text, "2 unread");
      keyClick(Qt.Key_A); compare(counter.text, "1 unread");
    }
    function test_older_backend_does_not_show_an_inclusive_or_fabricated_archive_count() {
      request("unreadCounts"); beeperData.respond("unreadCounts", {counts: {Telegram: 1}, allCounts: {Telegram: 5}});
      keyClick(Qt.Key_A); verify(!beeperData.unreadCountsReady);
      compare(findChild(panel, "beeperUnreadConversationCount").text, "— unread");
      keyClick(Qt.Key_A); verify(beeperData.unreadCountsReady);
      compare(findChild(panel, "beeperUnreadConversationCount").text, "1 unread");
    }
    function test_no_archived_unread_conversations_is_a_ready_zero() {
      request("unreadCounts"); beeperData.respond("unreadCounts", {counts: {Telegram: 1}, archivedCounts: {}});
      keyClick(Qt.Key_A); verify(beeperData.unreadCountsReady);
      compare(findChild(panel, "beeperUnreadConversationCount").text, "0 unread");
    }
    function test_demo_counter_matches_the_archive_only_filter() {
      beeperData.demo = true;
      beeperData.chats = beeperData.chats.map(chat => chat.id === "tg-archive" ? Object.assign({}, chat, {isMarkedUnread: true}) : chat);
      compare(beeperData.unreadConversationCount("telegram"), 2);
      keyClick(Qt.Key_A); compare(panel.filteredChats.length, 1);
      compare(beeperData.unreadConversationCount("telegram"), 1);
    }
    function test_manual_unread_visibility_and_escape_behaviour_stay_intact() {
      beeperData.chats = beeperData.chats.map(chat => chat.id === "tg-archive" ? Object.assign({}, chat, {isMarkedUnread: true}) : chat);
      verify(panel.filteredChats.some(chat => chat.id === "tg-archive"), "Do not reintroduce the n disappearance bug");
      keyClick(Qt.Key_A); verify(panel.showArchived); compare(panel.filteredChats.length, 1);
      verify(panel.filteredChats.every(chat => chat.isArchived));
      keyClick(Qt.Key_Escape); verify(!panel.showArchived); compare(closeSpy.count, 0);
      verify(panel.filteredChats.some(chat => chat.id === "tg-archive"));
    }
  }
}
