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
      beeperData.replaceChats([
        {id: "read-a", title: "Read A", network: "Telegram", isPinned: true},
        {id: "unread-b", title: "Unread B", network: "WhatsApp", unreadCount: 2},
        {id: "read-c", title: "Read C", network: "Telegram"},
        {id: "manual-d", title: "Manual D", network: "Telegram", unreadCount: 0, isMarkedUnread: true},
        {id: "unread-e", title: "Unread E", network: "Telegram", unreadCount: 4},
        {id: "priority-f", title: "Priority F", network: "Telegram", isLowPriority: true, unreadCount: 2},
        {id: "read-g", title: "Read G", network: "Signal"}
      ]);
      panel.chooseChat(0);
      beeperData.respond("messages", {items: [{id: "m1", chatID: "read-a", text: "Message"}], hasMore: false});
      tryCompare(panel, "restoringView", false); panel.focusNavigation(); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName, JSON.stringify({
        unreadFirst: panel.unreadFirst, selected: beeperData.currentChatID, index: panel.chatIndex,
        head: panel.filteredChats.slice(0, 5).map(chat => chat.id), tail: panel.filteredChats.slice(-3).map(chat => chat.id),
        pages: pending("chats").map(request => request.params), y: panel.chatList.contentY, origin: panel.chatList.originY}));
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
      beeperData.replaceChats([rows[4], rows[2], rows[0], rows[1], rows[3], rows[5], rows[6]]);
      compare(ids(panel.filteredChats), "unread-e,read-c,manual-d,read-a,unread-b,read-g");
      keyClick(Qt.Key_U);
      compare(ids(panel.filteredChats), "unread-e,read-c,read-a,unread-b,manual-d,read-g");
      compare(beeperData.currentChatID, "read-a"); compare(panel.chatIndex, 2);
    }
    function unreadQueue() {
      beeperData.replaceChats(readChats(40).concat([
        {id: "queue-a", title: "Queue A", unreadCount: 1},
        {id: "queue-b", title: "Queue B", isMarkedUnread: true},
        {id: "queue-c", title: "Queue C", unreadCount: 2}
      ]));
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
      compare(beeperData.currentChatID, "queue-b", "Keep the confirmed selection while Beeper is processing");
      verify(findChild(panel, "beeperUnreadBadge-queue-b").pending);
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
    function test_failed_read_keeps_confirmed_state_and_selection() {
      unreadQueue(); keyClick(Qt.Key_M);
      beeperData.respond("read", null, {message: "Offline"});
      compare(beeperData.currentChatID, "queue-b");
      verify(beeperData.chats.find(chat => chat.id === "queue-b").isMarkedUnread);
      compare(beeperData.lastError, "Offline");
    }
    function test_read_confirmed_by_a_later_catalog_refresh_advances_the_actual_selection_data() {
      return [{tag: "page", source: "chats"}, {tag: "full-state-snapshot", source: "chatStates"}];
    }
    function test_read_confirmed_by_a_later_catalog_refresh_advances_the_actual_selection(data) {
      unreadQueue();
      function snapshot(rows) {
        return {items: rows.map(chat => Object.assign({}, chat, {network: chat.network || "Telegram",
          unreadCount: chat.unreadCount || 0, isMarkedUnread: chat.isMarkedUnread === true,
          isLowPriority: chat.isLowPriority === true}))};
      }
      tryVerify(() => pending("chatStates").length === 1);
      beeperData.respond("chatStates", snapshot(beeperData.chats));
      keyClick(Qt.Key_M);
      // The write can return the old unread state before Beeper publishes the
      // updated catalog. Advancing must follow the confirmed state transition.
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: true});
      compare(beeperData.currentChatID, "queue-b");
      tryVerify(() => pending(data.source).length === 1);
      const rows = beeperData.chats.map(chat => chat.id === "queue-b"
        ? Object.assign({}, chat, {unreadCount: 0, isMarkedUnread: false}) : chat);
      beeperData.respond(data.source, snapshot(rows));
      compare(beeperData.currentChatID, "queue-c"); compare(panel.chatIndex, 1);
      wait(300); verify(panel.chatList.atYBeginning);
    }
    function test_late_catalog_read_does_not_override_subsequent_navigation() {
      unreadQueue(); keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: true});
      panel.chooseChat(0);
      beeperData.respond("chats", {items: beeperData.chats.map(chat => chat.id === "queue-b"
        ? Object.assign({}, chat, {unreadCount: 0, isMarkedUnread: false}) : chat)});
      compare(beeperData.currentChatID, "queue-a");
      compare(panel.pendingReadNavigation, null);
    }
    function test_late_catalog_read_does_not_switch_the_conversation_while_typing() {
      unreadQueue(); keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: true});
      panel.compose(); wait(0); panel.composer.text = "Keep writing here";
      beeperData.respond("chats", {items: beeperData.chats.map(chat => chat.id === "queue-b"
        ? Object.assign({}, chat, {unreadCount: 0, isMarkedUnread: false}) : chat)});
      compare(beeperData.currentChatID, "queue-b"); compare(panel.composer.text, "Keep writing here");
      verify(panel.composer.activeFocus); compare(panel.pendingReadNavigation, null);
    }
    function test_marking_unread_cancels_a_previous_read_navigation_intent() {
      unreadQueue(); keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: true});
      keyClick(Qt.Key_N); compare(panel.pendingReadNavigation, null);
      beeperData.respond("chats", {items: beeperData.chats.map(chat => chat.id === "queue-b"
        ? Object.assign({}, chat, {unreadCount: 0, isMarkedUnread: false}) : chat)});
      compare(beeperData.currentChatID, "queue-b");
    }
    function test_temporary_window_focus_loss_does_not_keep_selection_on_the_read_row() {
      unreadQueue(); keyClick(Qt.Key_M);
      panel.windowFocused = false;
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-c"); compare(panel.chatIndex, 1);
      verify(!panel.windowFocused);
      panel.windowFocused = true;
      wait(300); verify(panel.chatList.atYBeginning);
    }
    function test_badge_wait_is_visual_only_and_settles_without_looping() {
      unreadQueue(); wait(300);
      const row = findChild(panel, "beeperChatRow-queue-b");
      tryCompare(row, "height", findChild(panel, "beeperSidebar").selectedRowHeight);
      const height = row.height, y = panel.chatList.contentY;
      keyClick(Qt.Key_M);
      const pendingIndicator = findChild(panel, "beeperUnreadBadge-queue-b");
      verify(pendingIndicator.pending); verify(!pendingIndicator.animating);
      for (let frame = 0; frame < 22; ++frame) {
        wait(16);
        verify(!pendingIndicator.animating, "Pressing the badge adds no animation");
        fuzzyCompare(pendingIndicator.scale, 1, 0.001);
        fuzzyCompare(pendingIndicator.opacity, 1, 0.001);
      }
      compare(beeperData.currentChatID, "queue-b"); verify(beeperData.currentChat.isMarkedUnread);
      compare(pending("read").length, 1); compare(row.height, height); fuzzyCompare(panel.chatList.contentY, y, 0.5);
      panel.visible = false; verify(!pendingIndicator.animating);
      panel.visible = true; verify(!pendingIndicator.animating);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      verify(!pendingIndicator.pending);
      compare(beeperData.currentChatID, "queue-c", "The animation never delays confirmation or selection");
      tryCompare(pendingIndicator, "visible", false);
    }
    function test_badge_releases_on_failure_and_fades_out_after_a_fast_reply() {
      unreadQueue(); keyClick(Qt.Key_M);
      const pendingIndicator = findChild(panel, "beeperUnreadBadge-queue-b");
      verify(!pendingIndicator.animating);
      beeperData.respond("read", null, {message: "Offline"});
      verify(!pendingIndicator.pending); verify(pendingIndicator.visible);
      compare(beeperData.currentChatID, "queue-b"); verify(beeperData.currentChat.isMarkedUnread);
      tryCompare(pendingIndicator, "scale", 1);
      keyClick(Qt.Key_M); verify(pendingIndicator.pending);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      verify(!pendingIndicator.pending);
      compare(beeperData.currentChatID, "queue-c");
      tryCompare(pendingIndicator, "visible", false);
    }
    function test_pending_badge_keeps_its_number_and_yellow_with_and_without_selection() {
      unreadQueue(); keyClick(Qt.Key_M);
      const badge = findChild(panel, "beeperUnreadBadge-queue-b");
      const yellow = findChild(panel, "beeperUnreadBadge-queue-c").color;
      compare(badge.color, yellow);
      wait(350); compare(badge.color, yellow);
      panel.chooseChat(0); wait(250); compare(badge.color, yellow);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-a");
      panel.chooseChat(panel.filteredChats.findIndex(chat => chat.id === "queue-c")); panel.focusNavigation();
      keyClick(Qt.Key_M); wait(250);
      const digits = findChild(panel, "beeperUnreadDigits-queue-c");
      verify(digits.visible); compare(digits.text, "2");
    }
    function test_badge_pops_in_and_shrinks_out_without_an_extra_bounce() {
      const badge = findChild(panel, "beeperUnreadBadge-read-a");
      verify(!badge.visible);
      beeperData.markChatUnread("read-a");
      wait(80); verify(!badge.visible); verify(!badge.animating);
      verify(!beeperData.currentChat.isMarkedUnread);
      beeperData.respond("unread", {id: "read-a", unreadCount: 0, isMarkedUnread: true});
      let entryPeak = 0;
      for (let frame = 0; frame < 22; ++frame) {
        wait(16); entryPeak = Math.max(entryPeak, badge.scale);
        verify(badge.opacity >= 0 && badge.opacity <= 1);
      }
      verify(entryPeak > 1.08 && entryPeak < 1.2, "Entry must actually overshoot, not merely fade in");
      fuzzyCompare(badge.scale, 1, 0.001); verify(beeperData.currentChat.isMarkedUnread);
      beeperData.markChatRead("read-a"); wait(80);
      verify(!badge.animating); fuzzyCompare(badge.scale, 1, 0.001);
      beeperData.respond("read", {id: "read-a", unreadCount: 0, isMarkedUnread: false});
      verify(!beeperData.currentChat.isMarkedUnread, "State confirmation never waits for the pop");
      let previousScale = 1;
      for (let frame = 0; frame < 22; ++frame) {
        wait(16);
        verify(badge.scale <= previousScale + 0.001, "Exit only shrinks; it never grows first");
        if (frame === 2) verify(badge.scale < 0.85, "Exit is visible immediately after confirmation, without a slow start");
        previousScale = badge.scale;
        verify(badge.opacity >= 0 && badge.opacity <= 1);
      }
      verify(!badge.visible); fuzzyCompare(badge.scale, 0, 0.001);
    }
    function test_badge_pop_reverses_from_its_current_size_without_jumping() {
      const badge = findChild(panel, "beeperUnreadBadge-read-a");
      beeperData.markChatUnread("read-a");
      beeperData.respond("unread", {id: "read-a", unreadCount: 0, isMarkedUnread: true});
      wait(70); const openingScale = badge.scale;
      beeperData.markChatRead("read-a");
      beeperData.respond("read", {id: "read-a", unreadCount: 0, isMarkedUnread: false});
      fuzzyCompare(badge.scale, openingScale, 0.001);
      wait(70); const closingScale = badge.scale;
      beeperData.markChatUnread("read-a");
      fuzzyCompare(badge.scale, closingScale, 0.001);
      beeperData.respond("unread", {id: "read-a", unreadCount: 0, isMarkedUnread: true});
      wait(350); verify(badge.visible); fuzzyCompare(badge.scale, 1, 0.001);
      verify(!badge.animating);
    }
    function test_pending_unread_and_failure_never_show_an_unconfirmed_badge() {
      const badge = findChild(panel, "beeperUnreadBadge-read-a");
      const count = beeperData.unreadConversationCount("all");
      beeperData.markChatUnread("read-a");
      for (let frame = 0; frame < 12; ++frame) {
        wait(16); verify(!badge.visible); verify(!badge.animating);
        compare(beeperData.unreadConversationCount("all"), count);
      }
      beeperData.respond("unread", null, {message: "Offline"});
      verify(!badge.visible); verify(!badge.animating);
      compare(beeperData.unreadConversationCount("all"), count);
      beeperData.markChatUnread("read-a");
      beeperData.respond("unread", {id: "read-a", unreadCount: 0, isMarkedUnread: true});
      verify(badge.present); verify(badge.animating);
      compare(beeperData.unreadConversationCount("all"), count + 1);
      wait(350); verify(badge.visible); fuzzyCompare(badge.scale, 1, 0.001);
    }
    function test_read_reply_does_not_override_later_navigation() {
      unreadQueue(); keyClick(Qt.Key_M);
      panel.chooseChat(0);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-a");
    }
    function test_read_reply_does_not_override_returning_to_the_same_chat() {
      unreadQueue(); keyClick(Qt.Key_M);
      panel.chooseChat(0); panel.chooseChat(panel.filteredChats.findIndex(chat => chat.id === "queue-b"));
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
    function test_read_reply_with_new_unread_messages_does_not_steal_selection() {
      unreadQueue(); keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "queue-b", unreadCount: 1, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-b");
      compare(beeperData.chats.find(chat => chat.id === "queue-b").unreadCount, 1);
    }
    function test_scrolled_unread_queue_keeps_selection_near_the_same_screen_position_data() {
      return [{tag: "top", firstVisible: 50}, {tag: "middle", firstVisible: 48}, {tag: "bottom", firstVisible: 44}];
    }
    function test_scrolled_unread_queue_keeps_selection_near_the_same_screen_position(data) {
      beeperData.replaceChats(readChats(250).concat(Array.from({length: 100}, (_, index) =>
        ({id: "queue-" + index, title: "Unread " + index, unreadCount: 1}))));
      keyClick(Qt.Key_U); panel.chooseChat(50); panel.focusNavigation();
      wait(300);
      const list = panel.chatList;
      list.positionViewAtIndex(data.firstVisible, ListView.Beginning); wait(300);
      const before = list.contentY - list.originY;
      const highlight = findChild(panel, "beeperChatSelection");
      const focusY = highlight.y - list.contentY;
      keyClick(Qt.Key_M);
      compare(beeperData.currentChatID, "queue-50");
      beeperData.respond("read", {id: "queue-50", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-51"); compare(panel.chatIndex, 50);
      fuzzyCompare(highlight.y - list.contentY, focusY, 1, "No initial jump to the next row's old position");
      for (let frame = 0; frame < 20; ++frame) {
        wait(16);
        verify(Math.abs(list.contentY - list.originY - before) < 85, "Never follow the read row down the catalog");
        fuzzyCompare(highlight.y - list.contentY, focusY, 1, "The focus stays in the same screen slot throughout the reorder");
      }
      wait(300);
      compare(beeperData.currentChatID, "queue-51");
      verify(Math.abs(list.contentY - list.originY - before) < 85);
    }
    function test_multiple_quick_reads_wait_then_advance_exactly_one_conversation() {
      unreadQueue(); panel.chooseChat(0); panel.focusNavigation();
      keyClick(Qt.Key_M); keyClick(Qt.Key_M);
      compare(beeperData.currentChatID, "queue-a"); compare(panel.chatIndex, 0);
      compare(pending("read").length, 1);
      beeperData.respond("read", {id: "queue-a", unreadCount: 0, isMarkedUnread: false});
      compare(beeperData.currentChatID, "queue-b");
      keyClick(Qt.Key_M);
      beeperData.respond("read", {id: "queue-b", unreadCount: 0, isMarkedUnread: false});
      wait(300); compare(beeperData.currentChatID, "queue-c"); verify(panel.chatList.atYBeginning);
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
      beeperData.replaceChats(beeperData.chats.concat(readChats(35)));
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
      beeperData.replaceChats(beeperData.chats.concat(readChats(35)));
      panel.chatList.forceLayout(); wait(250);
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
      beeperData.replaceChats(beeperData.chats.concat(readChats(35)));
      beeperData.chatsInitialized = true; beeperData.hasMoreChats = true; beeperData.chatsCursor = "page-1";
      keyClick(Qt.Key_U); tryVerify(() => pending("chats").length === 1);
      beeperData.respond("chats", null, {message: "Offline"});
      verify(beeperData.chatsPaginationBlocked);
      wait(300); compare(pending("chats").length, 0);
      keyClick(Qt.Key_U); keyClick(Qt.Key_U); wait(200); compare(pending("chats").length, 0);
    }
    function test_empty_all_read_and_all_unread_lists_keep_their_original_order() {
      beeperData.replaceChats([]); keyClick(Qt.Key_U); verify(panel.unreadFirst); compare(panel.filteredChats.length, 0);
      beeperData.replaceChats(readChats(3)); compare(ids(panel.filteredChats), "read-0,read-1,read-2");
      beeperData.replaceChats(beeperData.chats.map(chat => Object.assign({}, chat, {unreadCount: 1})));
      compare(ids(panel.filteredChats), "read-0,read-1,read-2");
      keyClick(Qt.Key_U); compare(ids(panel.filteredChats), "read-0,read-1,read-2");
    }
  }
}
