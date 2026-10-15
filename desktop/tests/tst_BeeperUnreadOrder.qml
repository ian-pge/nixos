import QtQuick
import QtTest
import Quickshell

// Real keyboard/view routing, with an in-memory transport and no account writes.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  Window { id: window; width: 1280; height: 900; visible: true }
  TestResult { id: results }
  TestCase {
    name: "BeeperUnreadOrder"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function pending(method) { return beeperData.requests.filter(request => request.method === method); }
    function ids(rows) { return rows.map(chat => chat.id).join(","); }
    function readChats(count) {
      const rows = [];
      for (let i = 0; i < count; ++i) rows.push({id: "read-" + i, title: "Read " + i, network: "Telegram"});
      return rows;
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true});
      beeperData.chats = [
        {id: "read-a", title: "Read A", network: "Telegram", isPinned: true},
        {id: "unread-b", title: "Unread B", network: "WhatsApp", unreadCount: 2},
        {id: "read-c", title: "Read C", network: "Telegram"},
        {id: "manual-d", title: "Manual D", network: "Telegram", unreadCount: 0, isMarkedUnread: true},
        {id: "unread-e", title: "Unread E", network: "Telegram", unreadCount: 4},
        {id: "priority-f", title: "Priority F", network: "Telegram", isLowPriority: true, unreadCount: 2},
        {id: "read-g", title: "Read G", network: "Signal"}
      ];
      panel.chooseChat(0);
      beeperData.respond("messages", {items: [{id: "m1", chatID: "read-a", text: "Message"}], hasMore: false});
      tryCompare(panel, "restoringView", false); panel.focusNavigation(); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperUnreadOrder: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_u_toggles_stable_order_without_changing_chat_draft_selection_or_read_state() {
      const original = JSON.stringify(beeperData.chats);
      const normal = ids(panel.filteredChats);
      beeperData.draftText = "Keep my draft"; beeperData.replyToMessageID = "m1";
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 0);
      keyClick(Qt.Key_U);
      verify(panel.unreadFirst); compare(ids(panel.filteredChats), "unread-b,manual-d,unread-e,read-a,read-c,read-g");
      compare(panel.chatIndex, 3); compare(beeperData.currentChatID, "read-a");
      compare(panel.messageIndex, 0); compare(panel.navigation, "messages");
      compare(beeperData.draftText, "Keep my draft"); compare(beeperData.replyToMessageID, "m1");
      verify(findChild(panel, "beeperUnreadConversationCount").text.startsWith("↑ "));
      keyClick(Qt.Key_U);
      verify(!panel.unreadFirst); compare(ids(panel.filteredChats), normal); compare(panel.chatIndex, 0);
      compare(JSON.stringify(beeperData.chats), original);
      compare(pending("read").length, 0); compare(pending("unread").length, 0);
      compare(pending("messages").length, 0); compare(pending("send").length, 0);
      verify(!findChild(panel, "beeperUnreadConversationCount").text.startsWith("↑ "));
    }
    function test_live_read_changes_and_new_normal_order_are_respected() {
      keyClick(Qt.Key_U);
      beeperData.applyReadState("unread-b", {id: "unread-b", unreadCount: 0, isMarkedUnread: false});
      compare(ids(panel.filteredChats), "manual-d,unread-e,read-a,unread-b,read-c,read-g");
      beeperData.applyReadState("read-c", {id: "read-c", unreadCount: 0, isMarkedUnread: true});
      compare(ids(panel.filteredChats), "read-c,manual-d,unread-e,read-a,unread-b,read-g");
      const rows = beeperData.chats;
      beeperData.chats = [rows[4], rows[2], rows[0], rows[1], rows[3], rows[5], rows[6]];
      compare(ids(panel.filteredChats), "unread-e,read-c,manual-d,read-a,unread-b,read-g");
      keyClick(Qt.Key_U);
      compare(ids(panel.filteredChats), "unread-e,read-c,read-a,unread-b,manual-d,read-g");
      compare(beeperData.currentChatID, "read-a"); compare(panel.chatIndex, 2);
    }
    function unreadQueue() {
      beeperData.chats = readChats(40).concat([
        {id: "queue-a", title: "Queue A", unreadCount: 1},
        {id: "queue-b", title: "Queue B", isMarkedUnread: true},
        {id: "queue-c", title: "Queue C", unreadCount: 2}
      ]);
      panel.focusNavigation(); keyClick(Qt.Key_U); panel.chooseChat(1);
      beeperData.respond("messages", {items: [], hasMore: false});
      compare(beeperData.currentChatID, "queue-b");
      panel.focusNavigation();
    }
    function test_mark_read_advances_to_next_unread_without_following_the_read_chat() {
      unreadQueue();
      beeperData.draftText = "Keep the draft";
      keyClick(Qt.Key_M);
      compare(pending("read")[0].params.chatID, "queue-b");
      compare(beeperData.currentChatID, "queue-b", "Wait for Beeper confirmation");
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-c");
      compare(beeperData.localDrafts["queue-b"].text, "Keep the draft");
      compare(panel.chatIndex, 1); compare(panel.navigation, "chats");
      wait(300);
      verify(panel.chatList.atYBeginning, "Stay with the unread conversations at the top");
      // A later HTTP refresh must not restore the marked conversation's focus.
      beeperData.respond("chats", {items: beeperData.chats, hasMore: false});
      wait(50); compare(beeperData.currentChatID, "queue-c");
      verify(panel.chatList.atYBeginning);
    }
    function test_read_state_arriving_before_the_action_reply_does_not_scroll_down() {
      unreadQueue(); keyClick(Qt.Key_M);
      beeperData.applyReadState("queue-b", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      wait(300);
      verify(panel.chatList.atYBeginning, "A live read update must not drag the viewport to the read section");
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-c");
    }
    function test_failed_read_keeps_selection() {
      unreadQueue(); keyClick(Qt.Key_M);
      beeperData.respond("read", null, {message: "Offline"});
      compare(beeperData.currentChatID, "queue-b");
      verify(beeperData.currentChat.isMarkedUnread);
    }
    function test_read_reply_does_not_override_later_navigation() {
      unreadQueue(); keyClick(Qt.Key_M);
      panel.chooseChat(0);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-a");
    }
    function test_read_reply_does_not_override_returning_to_the_same_chat() {
      unreadQueue(); keyClick(Qt.Key_M);
      panel.chooseChat(0); panel.chooseChat(1);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-b");
    }
    function test_read_reply_does_not_override_a_changed_sort() {
      unreadQueue(); keyClick(Qt.Key_M); keyClick(Qt.Key_U);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-b"); verify(!panel.unreadFirst);
    }
    function test_last_unread_returns_to_top_when_no_unread_remains() {
      unreadQueue();
      beeperData.applyReadState("queue-a", {id: "queue-a", unreadCount: 0});
      beeperData.applyReadState("queue-c", {id: "queue-c", unreadCount: 0});
      keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "read-0");
      wait(300); verify(panel.chatList.atYBeginning);
    }
    function test_last_unread_row_selects_the_previous_remaining_unread() {
      unreadQueue(); panel.chooseChat(2); keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "queue-c", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-b"); compare(panel.chatIndex, 1);
    }
    function test_read_reply_with_new_unread_messages_keeps_selection() {
      unreadQueue(); keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "queue-b", unreadCount: 1, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-b"); compare(beeperData.currentChat.unreadCount, 1);
    }
    function test_normal_order_keeps_the_marked_conversation_open() {
      panel.chooseChat(1); keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "unread-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "unread-b"); verify(!panel.unreadFirst);
    }
    function test_network_priority_and_search_filters_keep_the_unread_order() {
      keyClick(Qt.Key_U); keyClick(Qt.Key_Tab);
      compare(panel.networkFilter, "telegram"); verify(panel.unreadFirst);
      compare(ids(panel.filteredChats), "manual-d,unread-e,read-a,read-c");
      keyClick(Qt.Key_A);
      compare(ids(panel.filteredChats), "priority-f");
      panel.openChatSearch(); wait(0); panel.searchField.text = "priority";
      compare(ids(panel.filteredChats), "priority-f");
      keyClick(Qt.Key_Escape); keyClick(Qt.Key_Tab);
      compare(panel.networkFilter, "whatsapp"); compare(panel.filteredChats.length, 0); verify(panel.unreadFirst);
      keyClick(Qt.Key_U); verify(!panel.unreadFirst); compare(panel.networkFilter, "whatsapp"); verify(panel.showLowPriority);
      keyClick(Qt.Key_A); compare(ids(panel.filteredChats), "unread-b");
    }
    function test_typing_search_modals_and_modifiers_do_not_toggle_the_order() {
      panel.compose(); keyClick(Qt.Key_U); compare(panel.composer.text, "u"); verify(!panel.unreadFirst);
      panel.focusNavigation(); panel.openChatSearch(); wait(0);
      keyClick(Qt.Key_U); compare(panel.searchField.text, "u"); verify(!panel.unreadFirst);
      keyClick(Qt.Key_Escape); panel.openConversationSearch(); wait(0);
      keyClick(Qt.Key_U); verify(!panel.unreadFirst);
      panel.focusNavigation(); keyClick(Qt.Key_U); verify(!panel.unreadFirst);
      keyClick(Qt.Key_Escape); panel.openModal("help"); wait(0);
      keyClick(Qt.Key_U); verify(!panel.unreadFirst); panel.closeModal();
      keyClick(Qt.Key_U, Qt.ControlModifier); keyClick(Qt.Key_U, Qt.AltModifier); keyClick(Qt.Key_U, Qt.ShiftModifier);
      verify(!panel.unreadFirst);
      panel.preparingRecording = true; keyClick(Qt.Key_U); verify(!panel.unreadFirst); panel.preparingRecording = false;
      panel.windowFocused = false; keyClick(Qt.Key_U); verify(!panel.unreadFirst); panel.windowFocused = true;
      panel.compose(); mouseClick(findChild(panel, "beeperComposerEmoji")); tryCompare(panel, "emojiPickerOpen", true);
      keyClick(Qt.Key_Slash);
      keyClick(Qt.Key_U); compare(findChild(panel, "beeperEmojiSearch").text, "u"); verify(!panel.unreadFirst);
      keyClick(Qt.Key_Escape); panel.focusNavigation(); keyClick(Qt.Key_U); verify(panel.unreadFirst);
    }
    function test_order_is_shared_between_monitors_and_survives_reopening() {
      const other = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: false, visible: false});
      try {
        panel.focusNavigation(); keyClick(Qt.Key_U);
        verify(other.unreadFirst); compare(ids(other.filteredChats), ids(panel.filteredChats));
        panel.active = false; panel.active = true; panel.focusNavigation();
        verify(panel.unreadFirst); compare(beeperData.currentChatID, "read-a");
        keyClick(Qt.Key_U); verify(!other.unreadFirst);
      } finally { other.destroy(); }
    }
    function test_explicit_sort_reveals_the_top_but_keeps_the_open_chat() {
      beeperData.chats = beeperData.chats.concat(readChats(35));
      panel.chooseChat(24); beeperData.respond("messages", {items: [], hasMore: false});
      const selected = beeperData.currentChatID;
      wait(30); verify(!panel.chatList.atYBeginning);
      keyClick(Qt.Key_U); wait(50);
      verify(panel.chatList.atYBeginning); compare(beeperData.currentChatID, selected);
      compare(panel.filteredChats[panel.chatIndex].id, selected);
      keyClick(Qt.Key_J);
      compare(beeperData.currentChatID, panel.filteredChats[panel.chatIndex].id);
      verify(beeperData.currentChatID !== selected);
    }
    function test_older_unread_chats_are_loaded_at_the_top_and_disabling_stops_prefetch() {
      beeperData.chats = beeperData.chats.concat(readChats(35));
      beeperData.chatsInitialized = true; beeperData.hasMoreChats = true; beeperData.chatsCursor = "page-1";
      wait(150); compare(pending("chats").length, 0);
      keyClick(Qt.Key_U);
      tryVerify(() => pending("chats").length === 1); compare(pending("chats")[0].params.cursor, "page-1");
      beeperData.respond("chats", {items: [{id: "old-unread", title: "Old reminder", network: "SMS", isMarkedUnread: true}], hasMore: true, oldestCursor: "page-2"});
      compare(panel.filteredChats[3].id, "old-unread");
      tryVerify(() => pending("chats").length === 1); compare(pending("chats")[0].params.cursor, "page-2");
      keyClick(Qt.Key_U); verify(!panel.unreadFirst);
      beeperData.respond("chats", {items: [{id: "older-read", title: "Older read", network: "SMS"}], hasMore: true, oldestCursor: "page-3"});
      wait(250); compare(pending("chats").length, 0);
      compare(panel.filteredChats[panel.filteredChats.length - 2].id, "old-unread");
      compare(beeperData.currentChatID, "read-a"); compare(pending("read").length, 0);
    }
    function test_pagination_failure_does_not_retry_in_a_loop() {
      beeperData.chats = beeperData.chats.concat(readChats(35));
      beeperData.chatsInitialized = true; beeperData.hasMoreChats = true; beeperData.chatsCursor = "page-1";
      keyClick(Qt.Key_U); tryVerify(() => pending("chats").length === 1);
      beeperData.respond("chats", null, {message: "Offline"});
      verify(beeperData.chatsPaginationBlocked);
      wait(300); compare(pending("chats").length, 0);
      keyClick(Qt.Key_U); keyClick(Qt.Key_U); wait(200); compare(pending("chats").length, 0);
    }
    function test_empty_all_read_and_all_unread_lists_keep_their_original_order() {
      beeperData.chats = []; keyClick(Qt.Key_U); verify(panel.unreadFirst); compare(panel.filteredChats.length, 0);
      beeperData.chats = readChats(3); compare(ids(panel.filteredChats), "read-0,read-1,read-2");
      beeperData.chats = beeperData.chats.map(chat => Object.assign({}, chat, {unreadCount: 1}));
      compare(ids(panel.filteredChats), "read-0,read-1,read-2");
      keyClick(Qt.Key_U); compare(ids(panel.filteredChats), "read-0,read-1,read-2");
    }
  }
}
