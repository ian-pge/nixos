import QtQuick
import QtTest
import Quickshell

// Local fixture only: no Beeper process, network, D-Bus notifications or mic.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  property var otherPanel: null
  property var format: null
  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") { Qt.exit(1); return; }
    const dc = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperData.qml");
    const pc = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperPanel.qml");
    if (dc.status !== Component.Ready || pc.status !== Component.Ready) { console.error(dc.errorString(), pc.errorString()); Qt.exit(1); return; }
    beeperData = dc.createObject(fixture, {demo: true});
    format = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../features/messenger/BeeperFormat.js" as F; QtObject { property var library: F }', fixture).library;
    panel = pc.createObject(window.contentItem, {width: 1280, height: 900, beeperData: beeperData, active: true, windowFocused: true});
    otherPanel = pc.createObject(window.contentItem, {width: 1280, height: 900, beeperData: beeperData, active: false, visible: false});
  }
  Window {
    id: window
    width: 1280; height: 900; visible: true
    onWidthChanged: if (fixture.panel) fixture.panel.width = width
  }
  SignalSpy { id: closeSpy; target: panel; signalName: "closeRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperPanel"
    when: window.visible && fixture.panel !== null && beeperData.messages.length > 0
    function cleanupTestCase() { wait(100); console.log("BeeperPanel: " + results.passCount + " passed, " + results.failCount + " failed"); Qt.exit(results.failCount ? 1 : 0); }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function child(name) { return findChild(panel, name); }
    function init() {
      otherPanel.active = false; otherPanel.visible = false;
      panel.active = true; panel.windowFocused = true;
      panel.closeModal(); panel.editMessageID = "";
      panel.pinLatest = false;
      beeperData.setChatTextSize(20);
      beeperData.selectChat("studio"); beeperData.draftText = ""; beeperData.draftAttachment = null; beeperData.replyToMessageID = "";
      panel.width = 1280; panel.messageIndex = -1; panel.chatIndex = 0;
      child("beeperSearch").text = "";
      panel.closeChatSearch();
      panel.focusNavigation(); closeSpy.clear(); wait(30);
    }
    function test_enter_sends_once_and_preserves_unicode() {
      panel.compose();
      const composer = child("beeperComposer"), before = beeperData.messages.length;
      composer.text = "Été à Paris, cœur et café 🌿";
      keyClick(Qt.Key_Return);
      tryCompare(beeperData, "sending", false);
      tryCompare(beeperData, "draftText", "");
      tryVerify(() => beeperData.messages.length === before + 1);
      compare(beeperData.messages[beeperData.messages.length - 1].text, "Été à Paris, cœur et café 🌿");
    }
    function test_sidebar_and_composer_backgrounds_are_fully_opaque() {
      const sidebar = child("beeperSidebar"), surface = child("beeperComposerSurface");
      compare(sidebar.color.a, 1); compare(surface.color.a, 1);
      compare(sidebar.color.toString(), "#24273a"); compare(surface.color.toString(), "#24273a");
      panel.compose(); verify(child("beeperComposer").activeFocus);
      compare(surface.color.a, 1);
      compare(surface.color.toString(), "#24273a", "Typing focus keeps the shared Macchiato Base");
      panel.focusNavigation(); panel.chooseChat(1);
      compare(sidebar.color.a, 1); compare(surface.color.a, 1);
    }
    function test_emoji_picker_owns_keyboard_without_changing_chat_or_sending() {
      panel.compose(); child("beeperComposer").text = "Keep this draft";
      child("beeperComposer").cursorPosition = 5;
      const chatID = beeperData.currentChatID, messageCount = beeperData.messages.length;
      const unread = beeperData.currentChat.isMarkedUnread;
      mouseClick(child("beeperComposerEmoji")); tryCompare(panel, "emojiPickerOpen", true);
      verify(!panel.canCycleNetwork); verify(!panel.canNavigateMessages);
      keyClick(Qt.Key_J, Qt.ControlModifier); keyClick(Qt.Key_K, Qt.ControlModifier);
      compare(panel.messageIndex, -1);
      keyClick(Qt.Key_N); keyClick(Qt.Key_M);
      compare(child("beeperEmojiSearch").text, "nm");
      compare(beeperData.currentChat.isMarkedUnread, unread);
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "all");
      keyClick(Qt.Key_Escape); tryCompare(panel, "emojiPickerOpen", false);
      compare(closeSpy.count, 0); verify(child("beeperComposer").activeFocus);
      compare(child("beeperComposer").cursorPosition, 5);
      compare(beeperData.draftText, "Keep this draft"); compare(beeperData.messages.length, messageCount);
      compare(beeperData.currentChatID, chatID);
    }
    function test_shift_enter_inserts_line_without_send() {
      panel.compose(); const before = beeperData.messages.length;
      child("beeperComposer").text = "Première ligne";
      keyClick(Qt.Key_Return, Qt.ShiftModifier);
      verify(child("beeperComposer").text.includes("\n"));
      compare(beeperData.messages.length, before);
    }
    function test_reply_composer_and_sent_message_keep_the_original() {
      panel.messageIndex = 0;
      const original = beeperData.messages[0];
      panel.replyToSelectedMessage(); wait(20);
      const quote = findChild(child("beeperComposerSurface"), "beeperQuote");
      verify(quote.visible); compare(quote.preview, fixture.format.text(original));
      child("beeperComposer").text = "A reply with its original attached";
      keyClick(Qt.Key_Return); tryCompare(beeperData, "sending", false);
      tryVerify(() => beeperData.messages.some(message => message.text === "A reply with its original attached"));
      const sent = beeperData.messages.find(message => message.text === "A reply with its original attached");
      compare(sent.linkedMessageID, original.id); verify(sent.isSender);
      compare(beeperData.replyToMessageID, ""); verify(!quote.visible);
    }
    function test_telegram_reader_updates_existing_bubbles_and_loaded_history() {
      const chats = beeperData.chats, messages = beeperData.messages;
      const list = child("beeperMessages");
      try {
        beeperData.chats = [{id: "studio", network: "Telegram", type: "single", title: "Camille", participants: {items: [
          {id: "self", isSelf: true}, {id: "camille", fullName: "Camille", isSelf: false}
        ]}}];
        beeperData.messages = [
          {id: "receipt-first", isSender: true, senderID: "self", text: "First", timestamp: "2026-09-25T10:00:00Z", seen: {self: true}},
          {id: "receipt-last", isSender: true, senderID: "self", text: "Last", timestamp: "2026-09-25T10:01:00Z", seen: {self: true}},
          {id: "receipt-incoming", senderID: "camille", text: "Incoming", timestamp: "2026-09-25T10:02:00Z", seen: {self: true}}
        ];
        wait(20);
        const first = list.itemAtIndex(0), last = list.itemAtIndex(1), incoming = list.itemAtIndex(2);
        verify(!findChild(incoming, "beeperMessageReadReceipt").visible);
        compare(first.readReceipt, ""); compare(last.readReceipt, "");
        beeperData.messages = fixture.format.mergeMessages(beeperData.messages, [Object.assign({}, beeperData.messages[1], {seen: {self: true, camille: true}})]);
        tryCompare(first, "readReceipt", "Read by Camille");
        tryCompare(last, "readReceipt", "Read by Camille");
        compare(list.itemAtIndex(0), first, "Updating receipts must reuse the existing bubbles");
        verify(findChild(first, "beeperMessageReadReceipt").visible);
        beeperData.messages = fixture.format.mergeMessages(beeperData.messages, [
          {id: "receipt-older", isSender: true, text: "Older page", timestamp: "2026-09-25T09:00:00Z"}
        ]);
        wait(20); compare(list.itemAtIndex(0).readReceipt, "Read by Camille");
        beeperData.chats = chats;
        tryCompare(first, "readReceipt", "", 1000);
      } finally { beeperData.chats = chats; beeperData.messages = messages; }
    }
    function test_ime_enter_does_not_send() {
      verify(!fixture.format.shouldSend(Qt.Key_Return, Qt.NoModifier, true));
      verify(!fixture.format.shouldSend(Qt.Key_Enter, Qt.ShiftModifier, false));
      verify(fixture.format.shouldSend(Qt.Key_Return, Qt.NoModifier, false));
    }
    function test_navigation_and_escape_hierarchy() {
      keyClick(Qt.Key_J); compare(beeperData.currentChatID, "lea");
      keyClick(Qt.Key_K); compare(beeperData.currentChatID, "studio");
      keyClick(Qt.Key_L); compare(panel.navigation, "messages");
      compare(panel.modal, "");
      keyClick(Qt.Key_I); verify(!child("beeperComposer").activeFocus);
      keyClick(Qt.Key_Return); verify(child("beeperComposer").activeFocus);
      keyClick(Qt.Key_Escape); verify(!child("beeperComposer").activeFocus); compare(closeSpy.count, 0);
      compare(panel.navigation, "chats");
      keyClick(Qt.Key_J); compare(beeperData.currentChatID, "lea");
      keyClick(Qt.Key_K); compare(beeperData.currentChatID, "studio"); wait(20);
      keyClick(Qt.Key_Return); verify(child("beeperComposer").activeFocus);
      keyClick(Qt.Key_Escape); compare(panel.navigation, "chats");
      panel.openModal("help"); wait(0);
      keyClick(Qt.Key_Escape); compare(panel.modal, ""); compare(closeSpy.count, 0);
      keyClick(Qt.Key_Escape); compare(closeSpy.count, 1);
    }
    function test_header_avatar_tracks_selected_conversation_and_network() {
      const header = child("beeperHeaderAvatar");
      verify(header.visible);
      compare(header.chat.id, "studio");
      panel.chooseChat(1); wait(10);
      compare(header.chat.id, "lea"); compare(header.network.key, "whatsapp");
      const rowAvatar = child("beeperChatAvatar-lea");
      verify(rowAvatar !== null);
      compare(header.avatarSource, rowAvatar.avatarSource);
      compare(header.accent, rowAvatar.accent);
      panel.chooseChat(2); wait(10);
      compare(header.chat.id, "design"); compare(header.network.key, "telegram");
    }
    function test_header_uses_total_members_not_the_truncated_participant_list() {
      const chats = beeperData.chats;
      try {
        beeperData.chats = chats.map(chat => chat.id === "studio" ? Object.assign({}, chat,
          {participants: {total: 234, hasMore: true, items: [{id: "one"}]}}) : chat);
        compare(child("beeperChatSubtitle").text, "234 members");
        compare(fixture.format.chatSubtitle({type: "group", participants: {total: 1}}), "1 member");
        compare(fixture.format.chatSubtitle({type: "group", participants: {items: [{id: "a"}], hasMore: true}}), "Group conversation");
        compare(fixture.format.chatSubtitle({type: "single", network: "Telegram"}), "");
      } finally { beeperData.chats = chats; }
    }
    function test_actions_palette_is_removed() {
      compare(child("beeperActionQuery"), null);
      keyClick(Qt.Key_Colon); compare(panel.modal, "");
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.modal, "");
      compare(panel.messageIndex, beeperData.messages.length - 1);
      panel.openModal("actions"); compare(panel.modal, "");
      const message = child("beeperMessages").itemAtIndex(panel.messageIndex);
      mouseClick(message, message.width / 2, message.height / 2, Qt.RightButton);
      compare(panel.modal, "");
    }
    function test_text_zoom_shortcuts_only_resize_messages_and_composer() {
      const title = child("beeperChatTitle"), titleSize = title.font.pixelSize;
      const sidebar = child("beeperChats"), sidebarWidth = sidebar.width;
      panel.compose();
      const composer = child("beeperComposer");
      composer.text = "Keep this draft while zooming";
      const cursor = composer.cursorPosition;
      keyClick(Qt.Key_Plus, Qt.ControlModifier); wait(30);
      compare(beeperData.chatTextSize, 22); compare(composer.font.pixelSize, 22);
      compare(child("messageBody").font.pixelSize, 22);
      compare(title.font.pixelSize, titleSize); compare(sidebar.width, sidebarWidth);
      compare(composer.text, "Keep this draft while zooming"); compare(composer.cursorPosition, cursor);
      verify(composer.activeFocus);
      compare(otherPanel.beeperData.chatTextSize, 22, "Zoom is shared across monitors");
      keyClick(Qt.Key_Minus, Qt.ControlModifier); compare(beeperData.chatTextSize, 20);
      keyClick(Qt.Key_Equal, Qt.ControlModifier); compare(beeperData.chatTextSize, 22);
      keyClick(Qt.Key_Plus, Qt.ControlModifier | Qt.ShiftModifier); compare(beeperData.chatTextSize, 24);
      keyClick(Qt.Key_0, Qt.ControlModifier); compare(beeperData.chatTextSize, 20);
      panel.windowFocused = false;
      keyClick(Qt.Key_Plus, Qt.ControlModifier); compare(beeperData.chatTextSize, 20);
      panel.windowFocused = true;
      panel.openModal("help"); wait(0);
      keyClick(Qt.Key_Plus, Qt.ControlModifier); compare(beeperData.chatTextSize, 20);
    }
    function test_ctrl_wheel_zooms_but_normal_wheel_and_sidebar_do_not() {
      const list = child("beeperMessages"), sidebar = child("beeperChats");
      mouseWheel(list, list.width / 2, list.height / 2, 0, 120, Qt.NoButton, Qt.ControlModifier);
      compare(beeperData.chatTextSize, 22);
      mouseWheel(list, list.width / 2, list.height / 2, 0, -120, Qt.NoButton, Qt.ControlModifier);
      compare(beeperData.chatTextSize, 20);
      mouseWheel(list, list.width / 2, list.height / 2, 0, -120);
      compare(beeperData.chatTextSize, 20);
      mouseWheel(sidebar, sidebar.width / 2, sidebar.height / 2, 0, 120, Qt.NoButton, Qt.ControlModifier);
      compare(beeperData.chatTextSize, 20);
      panel.changeTextSize(100); compare(beeperData.chatTextSize, 36);
      panel.changeTextSize(-100); compare(beeperData.chatTextSize, 14);
      panel.changeTextSize(0); compare(beeperData.chatTextSize, 20);
    }
    function test_child_views_have_no_implicit_panel_context() {
      // These views must also instantiate outside BeeperPanel: their data and
      // commands are connected explicitly, never through an outer QML id.
      const cases = [
        {file: "BeeperSidebar.qml", props: {chats: beeperData.chats, currentNetwork: fixture.format.networkBadge("all"), searchOpen: true}, control: "searchInput"},
        {file: "BeeperComposer.qml", props: {beeperData: beeperData}, control: "input"},
        {file: "BeeperConnection.qml", props: {beeperData: beeperData}, control: "tokenInput"}
      ];
      for (const item of cases) {
        const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/" + item.file);
        compare(component.status, Component.Ready, component.errorString());
        const view = component.createObject(window.contentItem, Object.assign({width: 500, height: 500, visible: false}, item.props));
        verify(view !== null, item.file);
        try {
          verify(view[item.control] !== null, item.file + " exposes its input control");
          view[item.control].text = "Local view input";
          compare(view[item.control].text, "Local view input");
          compare(panel.modal, "", "An isolated view must not command the panel");
          compare(beeperData.draftText, "", "An inactive isolated view must not edit a draft");
        } finally { view.destroy(); component.destroy(); }
      }
    }
    function test_tab_cycles_networks_and_logos() {
      const chats = beeperData.chats;
      try {
        beeperData.chats = chats.concat([
          {id: "instagram-test", title: "Instagram contact", network: "Instagram"},
          {id: "sms-test", title: "SMS contact", network: "Google Messages"}
        ]);
        compare(panel.networkFilter, "all");
        compare(panel.currentNetwork.name, "All");
        compare(child("beeperNetworkFilter").text, "\uf086");
        verify(!child("beeperSearch").visible);
        const networks = [
          {key: "telegram", chat: "design", count: 1, glyph: "\ue217"},
          {key: "whatsapp", chat: "lea", count: 2, glyph: "\uf232"},
          {key: "instagram", chat: "instagram-test", count: 1, glyph: "\uf16d"},
          {key: "sms", chat: "sms-test", count: 1, glyph: "\uf27a"}
        ];
        for (const network of networks) {
          keyClick(Qt.Key_Tab);
          compare(panel.networkFilter, network.key);
          compare(beeperData.currentChatID, network.chat);
          compare(panel.filteredChats.length, network.count);
          compare(child("beeperNetworkFilter").text, network.glyph);
          compare(child("beeperComposerMicrophone").color, child("beeperNetworkFilter").accent);
          compare(child("beeperComposerSendIcon").color, child("beeperNetworkFilter").accent);
        }
        keyClick(Qt.Key_Tab);
        compare(panel.networkFilter, "all");
        verify(panel.filteredChats.some(chat => chat.network === "Signal"));
        for (const key of ["sms", "instagram", "whatsapp", "telegram", "all"]) {
          keyClick(Qt.Key_Tab, Qt.ShiftModifier);
          compare(panel.networkFilter, key);
        }
      } finally { beeperData.chats = chats; }
    }
    function test_network_filter_includes_multiple_accounts() {
      const chats = beeperData.chats;
      try {
        beeperData.chats = chats.concat([{id: "telegram-work", title: "Work", network: "Telegram", accountID: "second-telegram-account"}]);
        keyClick(Qt.Key_Tab);
        compare(panel.filteredChats.length, 2);
        verify(panel.filteredChats.some(chat => chat.accountID === "second-telegram-account"));
        compare(otherPanel.networkFilter, "telegram");
        compare(otherPanel.filteredChats.length, 2);
        compare(beeperData.currentChatID, "design", "The hidden monitor must not change the selection");
      } finally { beeperData.chats = chats; }
    }
    function test_all_keeps_the_purple_logo_but_uses_each_conversations_platform_color() {
      const chats = beeperData.chats;
      try {
        beeperData.chats = chats.concat([
          {id: "instagram-colors", title: "Instagram contact", network: "Instagram"},
          {id: "sms-colors", title: "SMS contact", network: "Google Messages"},
          {id: "unknown-colors", title: "Unknown platform", network: "Unknown"}
        ]);
        beeperData.networkFilter = "all";
        const cases = [
          {id: "design", color: "#7dc4e4"}, {id: "lea", color: "#a6da95"},
          {id: "studio", color: "#8aadf4"}, {id: "instagram-colors", color: "#f5bde6"},
          {id: "sms-colors", color: "#8bd5ca"}, {id: "unknown-colors", color: "#939ab7"}
        ];
        for (const item of cases) {
          panel.chooseChat(panel.filteredChats.findIndex(chat => chat.id === item.id));
          wait(20);
          compare(panel.networkFilter, "all");
          compare(child("beeperNetworkFilter").accent.toString(), "#c6a0f6");
          const row = child("beeperChatRow-" + item.id);
          verify(row !== null); verify(row.chosen);
          compare(row.color.toString(), item.color);
          compare(child("beeperComposerMicrophone").color.toString(), item.color);
          compare(child("beeperComposerSendIcon").color.toString(), item.color);
          compare(otherPanel.conversationAccent.toString(), item.color);
          beeperData.messages = [{id: "platform-color-message", chatID: item.id, text: "Test", isSender: true}];
          const history = child("beeperMessages");
          tryVerify(() => history.count === 1 && history.itemAtIndex(0)?.message.id === "platform-color-message");
          compare(history.itemAtIndex(0).bubbleColor.toString(), item.color);
        }
      } finally {
        beeperData.chats = chats; beeperData.selectChat("studio");
      }
    }
    function test_network_switch_preserves_draft() {
      beeperData.draftText = "Keep this draft";
      beeperData.replyToMessageID = "1";
      keyClick(Qt.Key_Tab); wait(10);
      compare(beeperData.currentChatID, "design");
      verify(beeperData.draftText !== "Keep this draft");
      keyClick(Qt.Key_Tab, Qt.ShiftModifier);
      panel.chooseChat(panel.filteredChats.findIndex(chat => chat.id === "studio")); wait(10);
      compare(beeperData.draftText, "Keep this draft");
      compare(beeperData.replyToMessageID, "1");
    }
    function test_empty_network_clears_selection_without_losing_draft() {
      const chats = beeperData.chats;
      try {
        beeperData.draftText = "Safe in the previous conversation";
        beeperData.chats = chats.filter(chat => chat.network !== "Telegram");
        keyClick(Qt.Key_Tab); wait(10);
        compare(panel.networkFilter, "telegram");
        compare(panel.filteredChats.length, 0);
        compare(beeperData.currentChatID, "");
        compare(beeperData.messages.length, 0);
        compare(beeperData.draftText, "");
        verify(!child("beeperComposer").enabled);
        compare(beeperData.localDrafts.studio.text, "Safe in the previous conversation");
        keyClick(Qt.Key_Tab, Qt.ShiftModifier); wait(10);
        compare(beeperData.currentChatID, "studio");
        compare(beeperData.draftText, "Safe in the previous conversation");
      } finally { beeperData.chats = chats; }
    }
    function test_slash_search_is_temporary_and_escape_hides_it() {
      keyClick(Qt.Key_Slash); wait(0);
      verify(panel.searchOpen); verify(child("beeperSearch").activeFocus);
      child("beeperSearch").text = "Design";
      compare(panel.filteredChats.length, 1);
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "all");
      keyClick(Qt.Key_Escape);
      verify(!panel.searchOpen); verify(!child("beeperSearch").visible);
      compare(child("beeperSearch").text, ""); compare(closeSpy.count, 0);
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "telegram");
    }
    function test_tab_does_not_switch_network_while_typing_or_in_dialogs() {
      panel.compose();
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "all");
      keyClick(Qt.Key_Escape); panel.focusNavigation();
      panel.openModal("help"); wait(0);
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "all");
      panel.closeModal();
      panel.windowFocused = false;
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "all");
      panel.windowFocused = true;
    }
    function test_opening_chat_outside_filter_returns_to_all() {
      keyClick(Qt.Key_Tab); compare(panel.networkFilter, "telegram");
      panel.openChat("lea", ""); wait(10);
      compare(panel.networkFilter, "all"); compare(otherPanel.networkFilter, "all");
      compare(beeperData.currentChatID, "lea");
      compare(panel.filteredChats[panel.chatIndex].id, "lea");
    }
    function test_hidden_monitor_cannot_clear_view_or_notification_target() {
      panel.updateView(); verify(beeperData.viewFocused); compare(beeperData.viewOwner, panel);
      otherPanel.windowFocused = false; otherPanel.updateView();
      verify(beeperData.viewFocused); compare(beeperData.viewOwner, panel);
      panel.active = false; verify(!beeperData.viewFocused);
      panel.active = true; tryCompare(beeperData, "viewFocused", true);
    }
    function test_draft_survives_chat_switch_and_close() {
      beeperData.draftText = "Brouillon conservé"; beeperData.replyToMessageID = "1";
      panel.chooseChat(1); wait(10); compare(beeperData.draftText, "");
      panel.chooseChat(0); wait(10); compare(beeperData.draftText, "Brouillon conservé"); compare(beeperData.replyToMessageID, "1");
      panel.active = false; compare(beeperData.draftText, "Brouillon conservé");
    }
    function test_reconnection_does_not_ask_for_another_token() {
      const chats = beeperData.chats;
      try {
        beeperData.chats = [];
        for (const state of ["loading-token", "keyring-unavailable", "connecting", "offline"]) {
          beeperData.state = state;
          verify(child("beeperConnectionSurface").visible);
          verify(!child("beeperToken").visible, state + " must reuse the saved token");
          verify(child("beeperReconnect").visible);
        }
        beeperData.state = "needs-token"; verify(child("beeperToken").visible);
        beeperData.state = "invalid-token"; verify(child("beeperToken").visible);
        child("beeperToken").text = "fictional-test-token";
        beeperData.savingToken = true;
        verify(!child("beeperToken").enabled);
        beeperData.savingToken = false;
        compare(child("beeperToken").text, "fictional-test-token", "Keep input until saving succeeds");
        beeperData.tokenStored(); compare(child("beeperToken").text, "");
        beeperData.chats = chats; beeperData.state = "offline";
        verify(!child("beeperConnectionSurface").visible, "Keep the cached inbox while reconnecting");
      } finally {
        beeperData.chats = chats; beeperData.state = "demo"; beeperData.savingToken = false;
        child("beeperToken").text = "";
      }
    }
    function test_reconnection_card_is_content_sized_and_centered() {
      const chats = beeperData.chats, status = beeperData.statusMessage, error = beeperData.lastError;
      try {
        beeperData.chats = []; beeperData.state = "offline";
        beeperData.lastError = ""; beeperData.statusMessage = "Reconnecting automatically with your saved token…";
        wait(30);
        const card = child("beeperConnectionSurface");
        verify(card.visible);
        compare(card.width, 500);
        verify(card.height > 200 && card.height < 450, "Only a compact card should be tinted");
        fuzzyCompare(card.height, card.implicitHeight, 1);
        fuzzyCompare(card.x + card.width / 2, panel.width / 2, 1);
        fuzzyCompare(card.y + card.height / 2, panel.height / 2, 1);
        compare(child("beeperHeaderClose"), null);
        mouseClick(child("beeperConnectionClose")); compare(closeSpy.count, 1);
      } finally {
        beeperData.chats = chats; beeperData.state = "demo";
        beeperData.statusMessage = status; beeperData.lastError = error;
      }
    }
    function test_reconnection_card_scrolls_long_errors_in_small_panels() {
      const chats = beeperData.chats, error = beeperData.lastError;
      try {
        beeperData.chats = []; beeperData.state = "needs-token";
        beeperData.lastError = "A detailed connection error with context. ".repeat(70);
        panel.width = 480; panel.height = 420; wait(30);
        const card = child("beeperConnectionSurface"), scroll = child("beeperConnectionScroll");
        verify(card.width <= panel.width - 48);
        verify(card.y >= 90 && card.y + card.height <= panel.height - 90);
        verify(card.implicitHeight > card.height);
        verify(scroll.contentHeight > scroll.availableHeight);
        scroll.contentItem.contentY = scroll.contentHeight - scroll.availableHeight;
        wait(10);
        const close = child("beeperConnectionClose"), pos = close.mapToItem(scroll, 0, 0);
        verify(pos.x >= 0 && pos.x + close.width <= scroll.width);
        verify(pos.y >= 0 && pos.y + close.height <= scroll.height + 1, "Actions stay reachable by scrolling");
        mouseClick(close); compare(closeSpy.count, 1);
      } finally {
        panel.width = 1280; panel.height = 900;
        beeperData.chats = chats; beeperData.state = "demo"; beeperData.lastError = error;
      }
    }
    function test_connection_card_blocks_chat_actions_without_a_full_overlay() {
      try {
        panel.compose(); beeperData.state = "invalid-token"; wait(20);
        verify(child("beeperToken").activeFocus);
        verify(!child("beeperComposer").enabled);
        verify(!child("beeperNetworkFilter").enabled);
        verify(!child("beeperMessages").enabled);
        verify(!beeperData.viewFocused);
        panel.focusNavigation(); keyClick(Qt.Key_Tab);
        compare(panel.networkFilter, "all");
        child("beeperReconnect").forceActiveFocus();
        keyClick(Qt.Key_J); compare(beeperData.currentChatID, "studio");
        keyClick(Qt.Key_Colon); compare(panel.modal, "");
        keyClick(Qt.Key_Escape); compare(closeSpy.count, 1);
        beeperData.state = "demo"; wait(20);
        verify(child("beeperComposer").enabled); verify(child("beeperNetworkFilter").enabled);
        keyClick(Qt.Key_Tab); compare(panel.networkFilter, "telegram");
      } finally { beeperData.state = "demo"; }
    }
    function test_compact_layout_keeps_composer_inside_panel() {
      window.width = 700; wait(20);
      const composer = child("beeperComposer");
      verify(composer.width > 220);
      const pos = composer.mapToItem(panel, 0, 0);
      verify(pos.x >= 0 && pos.x + composer.width <= panel.width);
      window.width = 1280;
    }
    function test_demo_cannot_open_microphone() {
      panel.startRecording();
      compare(panel.recorder, null); verify(!panel.preparingRecording);
      verify(beeperData.lastError.includes("microphone")); beeperData.lastError = "";
    }
    function test_transfer_restores_scroll_without_marking_latest() {
      const rows = [];
      for (let i = 0; i < 45; ++i) rows.push({id: "scroll-" + i, chatID: "studio", text: "Message dans l’historique " + i, senderName: "Contact", timestamp: new Date(Date.now() + i * 1000).toISOString()});
      beeperData.demoMessages.studio = beeperData.demoMessages.studio.concat(rows);
      beeperData.loadMessages(false); wait(30); tryCompare(panel, "restoringView", false);
      const list = child("beeperMessages");
      list.positionViewAtIndex(6, ListView.Beginning); panel.updateView();
      verify(!beeperData.viewAtLatest);
      panel.active = false;
      otherPanel.visible = true; otherPanel.windowFocused = true; otherPanel.active = true;
      wait(30);
      compare(beeperData.viewOwner, otherPanel);
      verify(!beeperData.viewAtLatest);
      otherPanel.active = false; otherPanel.visible = false;
    }
    function test_viewing_and_typing_keep_unread_until_manual_action() {
      beeperData.chats = beeperData.chats.map(chat => chat.id === "studio" ? Object.assign({}, chat, {unreadCount: 3, isMarkedUnread: true}) : chat);
      panel.windowFocused = false; panel.updateView(); wait(220);
      compare(beeperData.currentChat.unreadCount, 3);
      panel.windowFocused = true;
      child("beeperMessages").positionViewAtEnd(); panel.updateView(); wait(220);
      compare(beeperData.currentChat.unreadCount, 3);
      panel.compose(); child("beeperComposer").text = "A draft is not a reply"; wait(350);
      compare(beeperData.currentChat.unreadCount, 3); verify(beeperData.currentChat.isMarkedUnread);
      panel.focusNavigation(); keyClick(Qt.Key_M);
      tryCompare(beeperData.currentChat, "unreadCount", 0);
      verify(!beeperData.currentChat.isMarkedUnread);
      compare(beeperData.draftText, "A draft is not a reply");
    }
    function test_n_marks_current_chat_unread_without_inventing_message_count() {
      const chats = beeperData.chats;
      try {
        beeperData.chats = chats.map(chat => Object.assign({}, chat, {unreadCount: 0, isMarkedUnread: false}));
        const badge = child("beeperUnreadBadge-studio");
        verify(badge !== null); verify(!badge.visible);
        keyClick(Qt.Key_N); wait(20);
        verify(beeperData.currentChat.isMarkedUnread); compare(beeperData.currentChat.unreadCount, 0);
        tryCompare(badge, "visible", true);
        verify(!beeperData.chats.find(chat => chat.id === "lea").isMarkedUnread);
        panel.chooseChat(1); wait(20); panel.chooseChat(0); wait(250);
        verify(beeperData.currentChat.isMarkedUnread, "Reopening must keep the manual unread flag");
        keyClick(Qt.Key_M); wait(20);
        verify(!beeperData.currentChat.isMarkedUnread); tryCompare(badge, "visible", false);
        panel.compose(); child("beeperComposer").text = "";
        keyClick(Qt.Key_N); wait(20);
        compare(child("beeperComposer").text, "n"); verify(!beeperData.currentChat.isMarkedUnread);
        panel.focusNavigation(); panel.openChatSearch(); wait(0);
        keyClick(Qt.Key_N); verify(!beeperData.currentChat.isMarkedUnread);
        panel.closeChatSearch(); panel.focusNavigation(); panel.openModal("help"); wait(0);
        keyClick(Qt.Key_N); verify(!beeperData.currentChat.isMarkedUnread);
      } finally { panel.closeModal(); panel.closeChatSearch(); beeperData.chats = chats; }
    }
    function test_unread_header_keeps_manual_flags_even_with_archive_state() {
      const chats = beeperData.chats;
      try {
        beeperData.chats = [
          {id: "studio", title: "One", network: "Telegram", unreadCount: 50},
          {id: "manual", title: "Two", network: "WhatsApp", unreadCount: 0, isMarkedUnread: true, isArchived: true},
          {id: "both", title: "Three", network: "WhatsApp", unreadCount: 3, isMarkedUnread: true},
          {id: "archive", title: "Archived", network: "Telegram", unreadCount: 7, isArchived: true}
        ];
        beeperData.networkFilter = "all";
        const counter = child("beeperUnreadConversationCount"), logo = child("beeperNetworkFilter");
        compare(counter.text, "3 unread"); compare(counter.parent, logo.parent);
        verify(panel.filteredChats.some(chat => chat.id === "manual"));
        verify(!panel.filteredChats.some(chat => chat.id === "archive"));
        verify(counter.x > logo.x);
        beeperData.networkFilter = "whatsapp"; compare(counter.text, "2 unread");
        beeperData.networkFilter = "all";
      } finally { beeperData.chats = chats; }
    }
    function test_message_text_is_plain_and_media_has_width() {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperMessage.qml");
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(window.contentItem, {width: 600, message: {id: "x", text: "<b>Du texte</b>", attachments: [{type: "image"}]}});
      verify(item !== null); wait(0);
      const body = findChild(item, "messageBody");
      compare(body.textFormat, Text.PlainText);
      verify(body.width > 350); verify(item.implicitHeight > 200); item.destroy();
    }
  }
}
