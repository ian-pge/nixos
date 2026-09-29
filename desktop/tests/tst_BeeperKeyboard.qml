import QtQuick
import QtTest
import QtMultimedia
import Quickshell

// Real keyboard routing with an in-memory transport: no reactions are sent.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  property var openedUrls: []
  property var copiedTexts: []
  property int recordStarts: 0
  property int recordStops: 0
  // Never instantiate the native CaptureSession or open the microphone.
  Component {
    id: fakeRecorder
    QtObject {
      required property string outputPath
      property bool recording: false
      property int duration: 1000
      signal finished(string path)
      signal failed(string message)
      function start() { ++fixture.recordStarts; recording = true; }
      function stop() { ++fixture.recordStops; recording = false; finished(outputPath); }
    }
  }
  Window { id: window; width: 1280; height: 900; visible: true }
  SignalSpy { id: closeSpy; target: fixture.panel; signalName: "closeRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperKeyboard"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props);
      verify(item !== null); return item;
    }
    function pending(method) { return beeperData.requests.filter(request => request.method === method); }
    function waitForHistory() {
      const history = findChild(panel, "beeperMessages");
      tryVerify(() => !history.loading && (!history.count || history.itemAtIndex(history.count - 1)?.viewportReady === true));
    }
    function silentAudio() {
      function bytes(value, count) {
        let result = "";
        for (let i = 0; i < count; ++i) result += String.fromCharCode((value >>> (i * 8)) & 255);
        return result;
      }
      const samples = 16000;
      const wave = "RIFF" + bytes(36 + samples, 4) + "WAVEfmt "
        + bytes(16, 4) + bytes(1, 2) + bytes(1, 2) + bytes(8000, 4) + bytes(8000, 4)
        + bytes(1, 2) + bytes(8, 2) + "data" + bytes(samples, 4) + String.fromCharCode(128).repeat(samples);
      const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      let encoded = "";
      for (let i = 0; i < wave.length; i += 3) {
        const bits = (wave.charCodeAt(i) << 16) | ((wave.charCodeAt(i + 1) || 0) << 8) | (wave.charCodeAt(i + 2) || 0);
        encoded += alphabet[(bits >>> 18) & 63] + alphabet[(bits >>> 12) & 63]
          + (i + 1 < wave.length ? alphabet[(bits >>> 6) & 63] : "=")
          + (i + 2 < wave.length ? alphabet[bits & 63] : "=");
      }
      return "data:audio/wav;base64," + encoded;
    }
    function selectAttachment(attachment) {
      beeperData.messages = [{id: "media-message", chatID: "chat-a", senderName: "Contact", attachments: [attachment]}];
      waitForHistory();
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 0); wait(20);
      return findChild(findChild(panel, "beeperMessages").itemAtIndex(0), "beeperMedia");
    }
    function init() {
      fixture.openedUrls = []; fixture.copiedTexts = [];
      fixture.recordStarts = 0; fixture.recordStops = 0;
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true, recorderFactory: fakeRecorder,
          linkOpener: url => { fixture.openedUrls = fixture.openedUrls.concat([url]); return true; },
          clipboardWriter: text => { fixture.copiedTexts = fixture.copiedTexts.concat([text]); }});
      beeperData.chats = [
        {id: "chat-a", title: "First chat", accountID: "account-a", capabilities: {reaction: 2}},
        {id: "chat-b", title: "Second chat", capabilities: {reaction: 2}}
      ];
      beeperData.accounts = [{id: "account-a", user: {id: "self"}}];
      beeperData.selectChat("chat-a");
      const messages = [];
      for (let i = 0; i < 8; ++i)
        messages.push({id: "message-" + i, chatID: "chat-a", senderName: "Contact", text: "Message " + i,
          timestamp: new Date(1700000000000 + i * 60000).toISOString()});
      beeperData.respond("messages", {items: messages, hasMore: false});
      tryCompare(panel, "restoringView", false);
      panel.focusNavigation(); closeSpy.clear(); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperKeyboard: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_number_keys_react_to_the_selected_message_data() {
      return [
        {tag: "default", network: "WhatsApp", emoji: ["👍", "😂", "💜", "🔥", "💯", "🤡"]},
        {tag: "telegram_in_all", network: "Telegram", emoji: ["👍", "🤣", "❤️", "🔥", "💯", "🤡"]}
      ];
    }
    function test_ctrl_s_opens_the_emoji_grid_from_navigation_and_composer_data() {
      return [{tag: "navigation", compose: false}, {tag: "composer", compose: true}];
    }
    function test_ctrl_s_opens_the_emoji_grid_from_navigation_and_composer(data) {
      beeperData.draftText = "Hello world";
      panel.composer.cursorPosition = 6;
      if (data.compose) panel.compose();
      keyClick(Qt.Key_S, Qt.ControlModifier); tryCompare(panel, "emojiPickerOpen", true);
      const picker = findChild(panel, "beeperEmojiPicker");
      tryVerify(() => picker.grid.activeFocus); compare(picker.searchInput.text, "");
      compare(picker.grid.currentIndex, 0);
      keyClick(Qt.Key_L); compare(picker.grid.currentIndex, 1);
      keyClick(Qt.Key_H); compare(picker.grid.currentIndex, 0);
      keyClick(Qt.Key_J); verify(picker.grid.currentIndex > 1);
      keyClick(Qt.Key_K); compare(picker.grid.currentIndex, 0);
      keyClick(Qt.Key_H); keyClick(Qt.Key_K); compare(picker.grid.currentIndex, 0);
      const chosen = picker.matches[0].emoji;
      keyClick(Qt.Key_Return); tryCompare(panel, "emojiPickerOpen", false);
      compare(beeperData.draftText, "Hello " + chosen + "world");
      verify(panel.composer.activeFocus); compare(beeperData.currentChatID, "chat-a");
      compare(pending("send").length, 0); compare(pending("react").length, 0);
    }
    function test_emoji_slash_focuses_search_and_hjkl_remain_text_there() {
      panel.compose(); keyClick(Qt.Key_S, Qt.ControlModifier); tryCompare(panel, "emojiPickerOpen", true);
      const picker = findChild(panel, "beeperEmojiPicker");
      keyClick(Qt.Key_Slash); tryVerify(() => picker.searchInput.activeFocus);
      compare(picker.searchInput.text, "");
      for (const key of [Qt.Key_H, Qt.Key_J, Qt.Key_K, Qt.Key_L]) keyClick(key);
      compare(picker.searchInput.text, "hjkl"); compare(picker.matches.length, 0);
      keyClick(Qt.Key_Return); verify(panel.emojiPickerOpen);
      picker.searchInput.text = "coeur"; tryVerify(() => picker.matches.length > 1);
      keyClick(Qt.Key_Down); verify(picker.grid.activeFocus);
      keyClick(Qt.Key_L); compare(picker.grid.currentIndex, 1);
      const chosen = picker.matches[1].emoji;
      keyClick(Qt.Key_Space); tryCompare(panel, "emojiPickerOpen", false);
      compare(beeperData.draftText, chosen); compare(pending("send").length, 0);
    }
    function test_ctrl_s_closes_picker_without_losing_selected_draft_text() {
      beeperData.draftText = "Keep this text"; panel.compose(); panel.composer.select(5, 9);
      keyClick(Qt.Key_S, Qt.ControlModifier); tryCompare(panel, "emojiPickerOpen", true);
      keyClick(Qt.Key_Slash); keyClick(Qt.Key_S, Qt.ControlModifier);
      tryCompare(panel, "emojiPickerOpen", false); verify(panel.composer.activeFocus);
      compare(panel.composer.selectedText, "this"); compare(beeperData.draftText, "Keep this text");
    }
    function preparedVoice() {
      return {path: "/tmp/fictional-voice.ogg", srcURL: "file:///tmp/fictional-voice.ogg", type: "voice-note"};
    }
    function test_ctrl_d_records_and_finishes_without_scrolling_or_sending_data() {
      return [{tag: "navigation", compose: false}, {tag: "composer", compose: true}];
    }
    function test_ctrl_d_records_and_finishes_without_scrolling_or_sending(data) {
      beeperData.deferRecording = true; beeperData.draftText = "Keep my caption";
      if (data.compose) panel.compose();
      const chatY = panel.chatList.contentY, messageY = findChild(panel, "beeperMessages").contentY;
      keyClick(Qt.Key_D, Qt.ControlModifier); tryCompare(panel, "preparingRecording", true);
      compare(pending("prepareRecording").length, 1); compare(fixture.recordStarts, 0);
      beeperData.respond("prepareRecording", preparedVoice());
      tryCompare(panel, "recording", true); compare(fixture.recordStarts, 1);
      keyClick(Qt.Key_D, Qt.ControlModifier); tryCompare(panel, "recording", false);
      compare(fixture.recordStops, 1); compare(beeperData.draftAttachment.path, preparedVoice().path);
      compare(beeperData.draftText, "Keep my caption"); compare(pending("send").length, 0);
      compare(panel.chatList.contentY, chatY); compare(findChild(panel, "beeperMessages").contentY, messageY);
    }
    function test_recording_shortcut_keeps_existing_attachment_and_edit_draft() {
      beeperData.deferRecording = true; beeperData.draftText = "Keep text"; panel.compose(); panel.composer.cursorPosition = 0;
      beeperData.draftAttachment = {type: "file", fileName: "Keep.pdf"};
      keyClick(Qt.Key_D, Qt.ControlModifier); compare(pending("prepareRecording").length, 0);
      compare(beeperData.draftAttachment.fileName, "Keep.pdf"); compare(beeperData.draftText, "Keep text");
      beeperData.draftAttachment = null; panel.editMessageID = "edit"; panel.editText = "Keep edit";
      keyClick(Qt.Key_D, Qt.ControlModifier); compare(pending("prepareRecording").length, 0);
      compare(panel.editText, "Keep edit");
    }
    function test_recording_can_be_finished_from_help_even_when_disconnected() {
      beeperData.deferRecording = true;
      keyClick(Qt.Key_D, Qt.ControlModifier); beeperData.respond("prepareRecording", preparedVoice());
      tryCompare(panel, "recording", true); panel.openModal("help"); wait(20);
      keyClick(Qt.Key_D, Qt.ControlModifier); tryCompare(panel, "recording", false);
      compare(panel.modal, "help"); compare(pending("send").length, 0);
      panel.closeModal(); beeperData.draftAttachment = null;
      keyClick(Qt.Key_D, Qt.ControlModifier); beeperData.respond("prepareRecording", preparedVoice());
      beeperData.state = "offline";
      keyClick(Qt.Key_D, Qt.ControlModifier); tryCompare(panel, "recording", false);
      compare(fixture.recordStops, 2);
    }
    function test_recording_preparation_is_cancelled_when_panel_closes_even_if_reopened() {
      beeperData.deferRecording = true;
      keyClick(Qt.Key_D, Qt.ControlModifier); verify(panel.preparingRecording);
      panel.active = false; panel.active = true;
      beeperData.respond("prepareRecording", preparedVoice()); wait(20);
      compare(fixture.recordStarts, 0); verify(!panel.preparingRecording);
      compare(pending("discardAttachment").length, 1); compare(beeperData.draftAttachment, null);
    }
    function test_ctrl_d_cancels_preparation_and_cannot_start_a_late_microphone() {
      beeperData.deferRecording = true;
      keyClick(Qt.Key_D, Qt.ControlModifier); verify(panel.preparingRecording);
      keyClick(Qt.Key_D, Qt.ControlModifier); verify(!panel.preparingRecording);
      compare(pending("prepareRecording").length, 1);
      beeperData.respond("prepareRecording", preparedVoice()); wait(20);
      compare(fixture.recordStarts, 0); compare(pending("discardAttachment").length, 1);
      compare(beeperData.draftAttachment, null); compare(pending("send").length, 0);
    }
    function test_ctrl_d_from_emoji_search_closes_picker_and_starts_recording() {
      beeperData.deferRecording = true;
      keyClick(Qt.Key_S, Qt.ControlModifier); tryCompare(panel, "emojiPickerOpen", true);
      keyClick(Qt.Key_Slash); keyClick(Qt.Key_D, Qt.ControlModifier);
      tryCompare(panel, "emojiPickerOpen", false); verify(panel.preparingRecording);
      beeperData.respond("prepareRecording", preparedVoice()); tryCompare(panel, "recording", true);
      compare(fixture.recordStarts, 1); compare(pending("send").length, 0);
    }
    function test_recording_shortcut_ignores_inactive_read_only_and_search_contexts_data() {
      return ["inactive", "unfocused", "readonly", "sending", "dictating", "search", "message-search", "help", "disconnected"].map(mode => ({tag: mode, mode: mode}));
    }
    function test_recording_shortcut_ignores_inactive_read_only_and_search_contexts(data) {
      beeperData.deferRecording = true;
      if (data.mode === "inactive") panel.active = false;
      else if (data.mode === "unfocused") panel.windowFocused = false;
      else if (data.mode === "readonly") beeperData.chats = [Object.assign({}, beeperData.currentChat, {isReadOnly: true})];
      else if (data.mode === "sending") beeperData.sending = true;
      else if (data.mode === "dictating") panel.dictating = true;
      else if (data.mode === "search") panel.openChatSearch();
      else if (data.mode === "message-search") panel.openConversationSearch();
      else if (data.mode === "help") panel.openModal("help");
      else if (data.mode === "disconnected") beeperData.state = "offline";
      wait(20); keyClick(Qt.Key_D, Qt.ControlModifier);
      compare(pending("prepareRecording").length, 0); compare(fixture.recordStarts, 0);
    }
    function test_question_mark_help_is_complete_and_keyboard_scrollable() {
      keyClick(Qt.Key_Question); tryCompare(panel, "modal", "help"); tryVerify(() => panel.modalSurface.activeFocus);
      const help = findChild(panel, "beeperKeyboardHelp"), scroll = findChild(panel, "beeperHelpScroll");
      tryVerify(() => scroll.height > 100 && scroll.height < panel.height);
      verify(scroll.contentHeight > scroll.height, "The complete shortcut list must be scrollable");
      const footer = findChild(panel, "beeperHelpFooter");
      verify(footer.visible); verify(footer.mapToItem(panel.modalSurface, 0, footer.height).y <= panel.modalSurface.height - 8);
      for (const shortcut of ["Ctrl + s", "Ctrl + d", "h / j / k / l", "Ctrl + /", "Shift + A", "1 👍", "6 🤡", "Ctrl + 0"])
        verify(help.text.includes(shortcut), "Missing shortcut: " + shortcut);
      verify(!help.text.includes("Ctrl + d / u"));
      const chat = beeperData.currentChatID, start = scroll.contentY;
      keyClick(Qt.Key_J); tryVerify(() => scroll.contentY > start);
      keyClick(Qt.Key_K); compare(scroll.contentY, start);
      keyClick(Qt.Key_PageDown); verify(scroll.contentY > start);
      keyClick(Qt.Key_End); verify(scroll.contentY >= scroll.contentHeight - scroll.height - 1);
      keyClick(Qt.Key_Home); compare(scroll.contentY, start);
      compare(beeperData.currentChatID, chat);
      keyClick(Qt.Key_Question); compare(panel.modal, "");
      panel.compose(); keyClick(Qt.Key_Question);
      compare(panel.modal, ""); compare(panel.composer.text, "?");
    }
    function selectLinkedMessage(text, links = [], attachments = []) {
      beeperData.messages = [{id: "links", chatID: "chat-a", text: text, links: links, attachments: attachments}];
      waitForHistory();
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.selectedMessage.id, "links");
    }
    function test_space_opens_one_distinct_link_without_a_popup() {
      selectLinkedMessage("Read https://one.example/page.", [
        {url: "https://one.example/page", title: "One"}, {url: "javascript:alert(1)"}
      ]);
      keyClick(Qt.Key_Space);
      compare(fixture.openedUrls, ["https://one.example/page"]); compare(panel.modal, "");
      compare(panel.selectedMessage.id, "links");
    }
    function test_multiple_links_use_j_k_enter_and_escape_without_moving_the_chat() {
      selectLinkedMessage("https://one.example/page https://two.example/page", [{url: "https://one.example/page", title: "First link"}]);
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "links");
      tryCompare(panel.modalSurface, "activeFocus", true);
      const list = findChild(panel, "beeperLinksList");
      compare(list.count, 2); compare(list.currentIndex, 0); compare(fixture.openedUrls.length, 0);
      keyClick(Qt.Key_J); compare(list.currentIndex, 1);
      keyClick(Qt.Key_J); compare(list.currentIndex, 1);
      keyClick(Qt.Key_K); compare(list.currentIndex, 0);
      keyClick(Qt.Key_K); compare(list.currentIndex, 0);
      keyClick(Qt.Key_J); keyClick(Qt.Key_Return);
      compare(fixture.openedUrls, ["https://two.example/page"]); compare(panel.modal, "");
      compare(beeperData.currentChatID, "chat-a"); compare(panel.selectedMessage.id, "links");
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "links");
      keyClick(Qt.Key_Escape); compare(panel.modal, "");
      compare(fixture.openedUrls.length, 1); compare(panel.linkChoices.length, 0);
    }
    function test_links_take_priority_over_a_media_attachment() {
      selectLinkedMessage("https://one.example/photo", [], [{type: "image"}]);
      keyClick(Qt.Key_Space);
      compare(fixture.openedUrls, ["https://one.example/photo"]); compare(panel.modal, "");
    }
    function test_space_stays_text_while_composing_or_searching_a_linked_message() {
      selectLinkedMessage("https://one.example/");
      keyClick(Qt.Key_Return); verify(panel.composer.activeFocus);
      keyClick(Qt.Key_Space); compare(panel.composer.text, " "); compare(fixture.openedUrls.length, 0);
      keyClick(Qt.Key_Escape); keyClick(Qt.Key_K, Qt.ControlModifier);
      panel.openChatSearch(); wait(0);
      keyClick(Qt.Key_Space); compare(panel.searchField.text, " "); compare(fixture.openedUrls.length, 0);
    }
    function test_changing_conversation_cancels_the_link_picker() {
      selectLinkedMessage("https://one.example/ https://two.example/");
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "links");
      beeperData.selectChat("chat-b");
      compare(panel.modal, ""); compare(panel.linkChoices.length, 0); compare(fixture.openedUrls.length, 0);
    }
    function test_number_keys_react_to_the_selected_message(data) {
      beeperData.chats = beeperData.chats.map(chat => chat.id === "chat-a"
        ? Object.assign({}, chat, {network: data.network, capabilities: {reaction: 2, allowedReactions: data.emoji}}) : chat);
      compare(beeperData.networkFilter, "all");
      keyClick(Qt.Key_1); compare(pending("react").length, 0);
      keyClick(Qt.Key_K, Qt.ControlModifier);
      compare(panel.messageIndex, 7);
      const emoji = data.emoji;
      for (let i = 0; i < emoji.length; ++i) {
        keyClick(Qt.Key_1 + i);
        compare(pending("react").length, 1);
        if (i > 0) {
          compare(pending("react")[0].params.reactionKey, emoji[i - 1]);
          verify(pending("react")[0].params.remove);
          beeperData.respond("react", {});
        }
        const params = pending("react")[0].params;
        compare(params.chatID, "chat-a"); compare(params.messageID, "message-7");
        compare(params.reactionKey, emoji[i]); verify(!params.remove);
        beeperData.respond("react", {});
        compare(beeperData.messages[7].reactions[0].reactionKey, emoji[i]);
        compare(pending("message")[0].params.messageID, "message-7");
        beeperData.respond("message", beeperData.messages[7]);
      }
      compare(panel.modal, "");
      keyClick(Qt.Key_7); compare(pending("react").length, 0);
      panel.openModal("help"); wait(0);
      const help = findChild(panel, "beeperKeyboardHelp");
      for (let i = 0; i < emoji.length; ++i) verify(help.text.includes((i + 1) + " " + emoji[i]));
    }
    function test_one_toggles_thumbs_up_without_removing_other_peoples_reactions() {
      beeperData.messages = beeperData.messages.map((message, index) => index === 7
        ? Object.assign({}, message, {reactions: [{id: "theirs", participantID: "contact", reactionKey: "👍"}]}) : message);
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_1);
      compare(pending("react")[0].params.reactionKey, "👍"); verify(!pending("react")[0].params.remove);
      beeperData.respond("react", {}); beeperData.respond("message", beeperData.messages[7]);
      compare(beeperData.messages[7].reactions.length, 2);
      keyClick(Qt.Key_1); verify(pending("react")[0].params.remove);
      beeperData.respond("react", {});
      compare(beeperData.messages[7].reactions.length, 1); compare(beeperData.messages[7].reactions[0].id, "theirs");
    }
    function test_telegram_thumbs_up_uses_the_allowed_unicode_variant() {
      beeperData.chats = [Object.assign({}, beeperData.currentChat,
        {network: "Telegram", capabilities: {reaction: 2, allowedReactions: ["👍\uFE0F", "❤️", "🔥"]}})];
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_1);
      compare(pending("react")[0].params.reactionKey, "👍\uFE0F");
      verify(!pending("react")[0].params.remove); compare(beeperData.lastError, "");
      beeperData.respond("react", {});
      beeperData.respond("message", Object.assign({}, beeperData.messages[7],
        {reactions: [{participantID: "self", reactionKey: "👍"}]}));
      keyClick(Qt.Key_1);
      compare(pending("react")[0].params.reactionKey, "👍");
      verify(pending("react")[0].params.remove, "The same emoji toggles off even with a different presentation selector");
    }
    function test_reaction_variants_do_not_bypass_allowed_skin_tones_or_sequences() {
      beeperData.chats = [Object.assign({}, beeperData.currentChat,
        {capabilities: {reaction: 2, allowedReactions: ["👍🏽", "❤️‍🔥"]}})];
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_1);
      compare(pending("react").length, 0); verify(!!beeperData.lastError);
    }
    function test_ctrl_navigation_preserves_draft_and_escape_returns_to_chats() {
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 7);
      keyClick(Qt.Key_Return); verify(panel.composer.activeFocus);
      for (let key = Qt.Key_1; key <= Qt.Key_6; ++key) keyClick(key);
      compare(panel.composer.text, "123456"); compare(pending("react").length, 0);
      keyClick(Qt.Key_K, Qt.ControlModifier);
      compare(panel.messageIndex, 7); verify(!panel.composer.activeFocus);
      keyClick(Qt.Key_K, Qt.ControlModifier);
      compare(panel.messageIndex, 6); verify(!panel.composer.activeFocus);
      compare(beeperData.draftText, "123456");
      keyClick(Qt.Key_Escape); compare(panel.navigation, "chats");
      compare(panel.messageIndex, -1); verify(!findChild(panel, "beeperMessages").itemAtIndex(6).selected);
      keyClick(Qt.Key_J, Qt.ControlModifier);
      compare(panel.messageIndex, 7); compare(beeperData.currentChatID, "chat-a");
      keyClick(Qt.Key_Escape); keyClick(Qt.Key_J);
      compare(beeperData.currentChatID, "chat-b"); compare(panel.messageIndex, -1);
      keyClick(Qt.Key_K); compare(beeperData.currentChatID, "chat-a");
      compare(beeperData.localDrafts["chat-a"].text, "123456");
    }
    function test_reaction_changes_preserve_other_participants_data() {
      return [{tag: "account_identity", participants: false}, {tag: "chat_identity", participants: true}];
    }
    function test_reaction_changes_preserve_other_participants(data) {
      if (data.participants) {
        beeperData.accounts = [];
        beeperData.chats = [Object.assign({}, beeperData.currentChat,
          {participants: {items: [{id: "self", isSelf: true}, {id: "contact", isSelf: false}]}})];
      }
      beeperData.messages = beeperData.messages.map((message, index) => index === 7
        ? Object.assign({}, message, {reactions: [{id: "mine", participantID: "self", reactionKey: "😂"},
          {id: "theirs", participantID: "contact", reactionKey: "🔥"}]}) : message);
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_3);
      compare(pending("react")[0].params.reactionKey, "😂"); verify(pending("react")[0].params.remove);
      beeperData.respond("react", {});
      compare(pending("react")[0].params.reactionKey, "💜"); verify(!pending("react")[0].params.remove);
      beeperData.respond("react", {});
      const updated = beeperData.messages[7];
      compare(updated.reactions.length, 2);
      compare(updated.reactions.find(reaction => reaction.participantID === "contact").id, "theirs");
      compare(updated.reactions.find(reaction => reaction.participantID === "self").reactionKey, "💜");
      beeperData.respond("message", updated);
      keyClick(Qt.Key_3);
      compare(pending("react")[0].params.reactionKey, "💜"); verify(pending("react")[0].params.remove);
      beeperData.respond("react", {});
      compare(beeperData.messages[7].reactions.length, 1);
      compare(beeperData.messages[7].reactions[0].id, "theirs");
      compare(pending("react").length, 0);
    }
    function test_fast_reaction_changes_are_serialized_and_last_choice_wins() {
      keyClick(Qt.Key_K, Qt.ControlModifier);
      keyClick(Qt.Key_2); keyClick(Qt.Key_3); keyClick(Qt.Key_4);
      compare(pending("react").length, 1); compare(pending("react")[0].params.reactionKey, "😂");
      beeperData.respond("react", {});
      compare(pending("react").length, 1); verify(pending("react")[0].params.remove);
      compare(pending("react")[0].params.reactionKey, "😂");
      beeperData.respond("react", {});
      compare(pending("react").length, 1); verify(!pending("react")[0].params.remove);
      compare(pending("react")[0].params.reactionKey, "🔥");
      beeperData.respond("react", {});
      compare(pending("react").length, 0);
      compare(beeperData.messages[7].reactions.length, 1);
      compare(beeperData.messages[7].reactions[0].reactionKey, "🔥");
    }
    function test_stale_reaction_refresh_cannot_restore_previous_choice() {
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_2);
      beeperData.respond("react", {});
      const stale = beeperData.messages[7];
      compare(pending("message").length, 1);
      keyClick(Qt.Key_3); beeperData.respond("react", {}); beeperData.respond("react", {});
      compare(beeperData.messages[7].reactions[0].reactionKey, "💜");
      beeperData.respond("message", stale);
      compare(beeperData.messages[7].reactions[0].reactionKey, "💜");
      compare(pending("message").length, 1);
      // The API acknowledges a queued write before all reads reflect it.
      beeperData.respond("message", stale);
      compare(beeperData.messages[7].reactions[0].reactionKey, "💜");
      compare(Object.keys(beeperData.reactionOperations).length, 0);
    }
    function test_reaction_failure_stops_replacement_and_restricted_emoji_keeps_previous() {
      beeperData.messages = beeperData.messages.map((message, index) => index === 7
        ? Object.assign({}, message, {reactions: [{participantID: "self", reactionKey: "💜"}]}) : message);
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_1);
      verify(pending("react")[0].params.remove);
      beeperData.respond("react", null, {message: "Rejected"});
      compare(pending("react").length, 0); compare(pending("message").length, 0);
      compare(beeperData.messages[7].reactions[0].reactionKey, "💜");
      beeperData.chats = [Object.assign({}, beeperData.currentChat, {capabilities: {reaction: 2, allowedReactions: ["💜"]}})];
      keyClick(Qt.Key_1); compare(pending("react").length, 0);
      verify(!!beeperData.lastError); compare(beeperData.messages[7].reactions[0].reactionKey, "💜");
    }
    function test_reaction_refresh_targets_older_selected_message() {
      keyClick(Qt.Key_K, Qt.ControlModifier); panel.moveMessageSelection(-7);
      compare(panel.messageIndex, 0); keyClick(Qt.Key_5);
      compare(pending("react")[0].params.messageID, "message-0");
      beeperData.respond("react", {});
      compare(pending("message")[0].params.messageID, "message-0");
      compare(pending("messages").length, 0);
      beeperData.respond("message", beeperData.messages[0]);
      compare(panel.messageIndex, 0);
      compare(beeperData.messages[0].reactions[0].reactionKey, "💯");
      verify(!beeperData.messages[7].reactions?.length);
    }
    function test_selection_restarts_at_latest_after_leaving_history_data() {
      return ["sidebar", "compose", "mouse", "window", "panel"].map(mode => ({tag: mode, mode: mode}));
    }
    function test_selection_restarts_at_latest_after_leaving_history(data) {
      keyClick(Qt.Key_K, Qt.ControlModifier); panel.moveMessageSelection(-3);
      compare(panel.messageIndex, 4);
      if (data.mode === "sidebar") keyClick(Qt.Key_Escape);
      else if (data.mode === "compose") keyClick(Qt.Key_Return);
      else if (data.mode === "mouse") mouseClick(panel.composer, 20, 20);
      else if (data.mode === "window") { panel.windowFocused = false; panel.windowFocused = true; }
      else { panel.active = false; panel.active = true; wait(20); }
      compare(panel.selectedMessage, null);
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 7);
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 6);
    }
    function test_reply_then_reenter_history_selects_newest_message() {
      keyClick(Qt.Key_K, Qt.ControlModifier); panel.moveMessageSelection(-3);
      keyClick(Qt.Key_R); compare(beeperData.replyToMessageID, "message-4");
      compare(panel.selectedMessage, null);
      beeperData.draftText = "My reply"; keyClick(Qt.Key_Return);
      compare(pending("send")[0].params.replyToMessageID, "message-4");
      beeperData.respond("send", {chatID: "chat-a", pendingMessageID: "sent"});
      beeperData.respond("messages", {items: beeperData.messages.concat([
        {id: "sent", chatID: "chat-a", text: "My reply", isSender: true, timestamp: "2026-09-26T10:00:00Z"}
      ]), hasMore: false});
      waitForHistory();
      compare(panel.selectedMessage, null);
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.selectedMessage.id, "sent");
    }
    function test_refresh_cannot_restore_selection_after_returning_to_sidebar() {
      keyClick(Qt.Key_K, Qt.ControlModifier); panel.moveMessageSelection(-3);
      beeperData.messagesUpdating();
      panel.focusNavigation();
      beeperData.messagesLoaded(false);
      compare(panel.selectedMessage, null);
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 7);
    }
    function test_escape_cancels_reply_or_edit_before_leaving_composer_data() {
      return [{tag: "reply", edit: false}, {tag: "edit", edit: true}];
    }
    function test_escape_cancels_reply_or_edit_before_leaving_composer(data) {
      beeperData.messages = [{id: "original", chatID: "chat-a", isSender: true, text: "Message original"}];
      waitForHistory();
      beeperData.draftText = "Brouillon conservé";
      beeperData.draftAttachment = {type: "file", fileName: "notes.txt"};
      keyClick(Qt.Key_K, Qt.ControlModifier);
      keyClick(data.edit ? Qt.Key_E : Qt.Key_R);
      if (data.edit) {
        compare(panel.editMessageID, "original"); compare(panel.composer.text, "Message original");
      } else compare(beeperData.replyToMessageID, "original");
      verify(panel.composer.activeFocus);

      keyClick(Qt.Key_Escape);
      compare(beeperData.replyToMessageID, ""); compare(panel.editMessageID, "");
      verify(!findChild(findChild(panel, "beeperComposerSurface"), "beeperQuote").visible);
      verify(panel.composer.activeFocus); compare(panel.navigation, "compose");
      compare(panel.composer.text, "Brouillon conservé");
      compare(beeperData.draftText, "Brouillon conservé");
      compare(beeperData.draftAttachment.fileName, "notes.txt");
      compare(panel.selectedMessage, null); compare(closeSpy.count, 0);

      keyClick(Qt.Key_Escape);
      compare(beeperData.draftAttachment, null);
      verify(panel.composer.activeFocus); compare(panel.navigation, "compose");
      compare(panel.composer.text, "Brouillon conservé"); compare(closeSpy.count, 0);

      keyClick(Qt.Key_Escape);
      compare(panel.navigation, "chats"); verify(!panel.composer.activeFocus);
      compare(closeSpy.count, 0);
      keyClick(Qt.Key_Escape); compare(closeSpy.count, 1);
    }
    function test_escape_removes_attachment_before_leaving_composer_data() {
      return [{tag: "with_text", text: "Brouillon conservé"}, {tag: "attachment_only", text: ""}];
    }
    function test_escape_removes_attachment_before_leaving_composer(data) {
      beeperData.draftText = data.text;
      beeperData.draftAttachment = {type: "file", fileName: "notes.txt", path: "/fixture/attachments/notes.txt"};
      keyClick(Qt.Key_Return);
      const surface = findChild(panel, "beeperComposerSurface");
      verify(panel.composer.activeFocus); verify(surface.sendMode);

      keyClick(Qt.Key_Escape);
      compare(beeperData.draftAttachment, null);
      compare(beeperData.localDrafts["chat-a"].attachment, null);
      compare(beeperData.localDrafts["chat-a"].text, data.text);
      compare(beeperData.draftText, data.text); compare(panel.composer.text, data.text);
      verify(panel.composer.activeFocus); compare(panel.navigation, "compose");
      compare(surface.sendMode, !!data.text); compare(closeSpy.count, 0);
      compare(pending("send").length, 0);

      keyClick(Qt.Key_Escape);
      compare(panel.navigation, "chats"); verify(!panel.composer.activeFocus);
      compare(closeSpy.count, 0);
      keyClick(Qt.Key_J); compare(beeperData.currentChatID, "chat-b");
    }
    function test_reactions_respect_chat_capabilities_and_read_only_state() {
      keyClick(Qt.Key_K, Qt.ControlModifier);
      for (const capability of [false, 0, -1]) {
        beeperData.chats = [{id: "chat-a", capabilities: {reaction: capability}}];
        keyClick(Qt.Key_2); compare(pending("react").length, 0);
      }
      beeperData.chats = [{id: "chat-a", capabilities: {reaction: 2}, isReadOnly: true}];
      keyClick(Qt.Key_3); compare(pending("react").length, 0);
      keyClick(Qt.Key_Return); verify(!panel.composer.activeFocus);
      beeperData.chats = [{id: "chat-a", capabilities: {reaction: 2}}];
      beeperData.state = "offline";
      panel.reactToSelectedMessage("🔥"); compare(pending("react").length, 0);
    }
    function test_reaction_completion_cannot_reload_another_conversation() {
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_6);
      compare(pending("react")[0].params.reactionKey, "🤡");
      compare(pending("react")[0].params.messageID, "message-7");
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 6);
      compare(pending("react")[0].params.messageID, "message-7");
      panel.chooseChat(1); compare(beeperData.currentChatID, "chat-b");
      compare(pending("messages").length, 1);
      beeperData.respond("react", {});
      compare(pending("messages").length, 1);
      verify(!beeperData.trailingMessagesRefresh);
      compare(pending("messages")[0].params.chatID, "chat-b");
    }
    function test_shortcuts_do_not_escape_search_dialog_or_inactive_window() {
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 7);
      panel.openChatSearch(); wait(0);
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 7);
      keyClick(Qt.Key_1); keyClick(Qt.Key_6); compare(panel.searchField.text, "16"); compare(pending("react").length, 0);
      keyClick(Qt.Key_Escape);
      panel.openModal("help"); wait(0);
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_2);
      compare(panel.messageIndex, 7); compare(pending("react").length, 0);
      keyClick(Qt.Key_Escape); panel.windowFocused = false;
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_3);
      compare(panel.messageIndex, -1); compare(pending("react").length, 0);
    }
    function test_opening_another_chat_clears_the_previous_message_selection() {
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 7);
      panel.openChat("chat-b", "");
      compare(panel.messageIndex, -1);
      beeperData.respond("messages", {items: [{id: "message-7", chatID: "chat-b", text: "A different chat"}], hasMore: false});
      tryCompare(panel, "restoringView", false);
      keyClick(Qt.Key_1); compare(pending("react").length, 0);
    }
    function test_space_opens_selected_video_and_preserves_selection_on_close() {
      const media = selectAttachment({type: "video", srcURL: "file://" + Quickshell.shellDir + "/fixtures/fullscreen-video.mp4", duration: 20});
      const inlinePlayer = findChild(media, "beeperMediaPlayer"); verify(inlinePlayer !== null);
      inlinePlayer.play(); tryCompare(inlinePlayer, "playbackState", MediaPlayer.PlayingState);
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "media");
      verify(panel.photoPreviewOpen); verify(panel.videoPreviewOpen);
      const viewer = findChild(panel, "beeperPhotoViewer");
      tryCompare(viewer, "activeFocus", true);
      tryVerify(() => inlinePlayer.playbackState !== MediaPlayer.PlayingState);
      const fullscreenPlayer = findChild(viewer, "beeperMediaPlayer"); verify(fullscreenPlayer !== null);
      tryCompare(fullscreenPlayer, "playbackState", MediaPlayer.PlayingState, 3000);
      keyClick(Qt.Key_Space); tryCompare(fullscreenPlayer, "playbackState", MediaPlayer.PausedState);
      compare(panel.modal, "media"); compare(panel.messageIndex, 0);
      keyClick(Qt.Key_Escape); tryCompare(panel, "modal", "");
      compare(panel.selectedMessage.id, "media-message"); compare(closeSpy.count, 0);
      verify(inlinePlayer.playbackState !== MediaPlayer.PlayingState);
    }
    function test_space_toggles_selected_audio_and_stays_text_in_composer() {
      const media = selectAttachment({type: "audio", srcURL: silentAudio(), duration: 2});
      const player = findChild(media, "beeperMediaPlayer"); verify(player !== null);
      player.audioOutput.muted = true;
      keyClick(Qt.Key_Space); tryCompare(player, "playbackState", MediaPlayer.PlayingState);
      keyClick(Qt.Key_Space); tryCompare(player, "playbackState", MediaPlayer.PausedState);
      compare(panel.modal, "");
      keyClick(Qt.Key_Return); verify(panel.composer.activeFocus);
      keyClick(Qt.Key_Space); compare(panel.composer.text, " ");
      compare(player.playbackState, MediaPlayer.PausedState);
    }
    function startVoice() {
      const media = selectAttachment({id: "voice-asset", type: "audio", srcURL: silentAudio(), duration: 2});
      const player = beeperData.audioPlayback.player;
      player.audioOutput.muted = true;
      keyClick(Qt.Key_Space); tryCompare(player, "playbackState", MediaPlayer.PlayingState);
      return media;
    }
    function test_voice_survives_reaction_updates_scrolling_typing_and_chat_changes() {
      const media = startVoice(), player = beeperData.audioPlayback.player;
      const key = beeperData.audioPlayback.key, source = player.source;
      keyClick(Qt.Key_1); beeperData.respond("react", {});
      beeperData.respond("message", beeperData.messages[0]);
      compare(player.playbackState, MediaPlayer.PlayingState);
      const row = findChild(panel, "beeperMessages").itemAtIndex(0);
      row.renderMedia = false; wait(10);
      compare(player.playbackState, MediaPlayer.PlayingState, "Offscreen delegate unloading must not pause");
      panel.compose(); keyClick(Qt.Key_A); keyClick(Qt.Key_Return);
      verify(pending("send").length > 0); compare(player.playbackState, MediaPlayer.PlayingState);
      panel.chooseChat(1);
      beeperData.respond("messages", {items: [], hasMore: false});
      panel.active = false; panel.visible = false; wait(20);
      compare(beeperData.audioPlayback.key, key); compare(player.source, source);
      compare(player.playbackState, MediaPlayer.PlayingState, "Changing or hiding the conversation must not stop a voice note");
    }
    function test_voice_controls_reattach_after_delegate_recreation() {
      startVoice();
      const player = beeperData.audioPlayback.player, saved = beeperData.messages[0];
      player.playbackRate = 1.5;
      beeperData.messages = []; wait(0);
      compare(player.playbackState, MediaPlayer.PlayingState);
      beeperData.messages = [JSON.parse(JSON.stringify(saved))]; wait(20);
      waitForHistory();
      keyClick(Qt.Key_K, Qt.ControlModifier);
      const media = findChild(findChild(panel, "beeperMessages").itemAtIndex(0), "beeperMedia");
      verify(media.currentAudio); compare(findChild(media, "beeperMediaRate").text, "1.5×");
      keyClick(Qt.Key_Space); tryCompare(player, "playbackState", MediaPlayer.PausedState);
    }
    function test_voice_escape_pauses_from_every_chat_surface_data() {
      return ["navigation", "composer", "help", "photo", "emoji", "search"].map(mode => ({tag: mode, mode: mode}));
    }
    function test_voice_escape_pauses_from_every_chat_surface(data) {
      startVoice(); const player = beeperData.audioPlayback.player;
      if (data.mode === "composer") panel.compose();
      else if (data.mode === "help") panel.openModal("help");
      else if (data.mode === "photo") {
        panel.previewAttachment = {type: "img", srcURL: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="5" height="5"/>')};
        panel.openModal("media");
      } else if (data.mode === "emoji") findChild(panel, "beeperComposerSurface").toggleEmojiPicker();
      else if (data.mode === "search") panel.openChatSearch();
      wait(20); compare(player.playbackState, MediaPlayer.PlayingState);
      keyClick(Qt.Key_Escape); tryCompare(player, "playbackState", MediaPlayer.PausedState);
      verify(!beeperData.audioPlayback.playWhenReady);
    }
    function test_another_voice_cannot_interrupt_the_current_one() {
      startVoice(); const key = beeperData.audioPlayback.key;
      beeperData.audioPlayback.play("another-message", {type: "audio", srcURL: "mxc://preview/another"});
      compare(beeperData.audioPlayback.key, key); compare(pending("download").length, 0);
      compare(beeperData.audioPlayback.player.playbackState, MediaPlayer.PlayingState);
    }
    function test_pending_voice_survives_chat_changes_and_escape_prevents_late_playback_data() {
      return [{tag: "continue", cancel: false}, {tag: "escape", cancel: true}];
    }
    function test_pending_voice_survives_chat_changes_and_escape_prevents_late_playback(data) {
      selectAttachment({type: "audio", srcURL: "mxc://preview/voice", duration: 2});
      keyClick(Qt.Key_Space); tryCompare(beeperData.audioPlayback, "playWhenReady", true);
      const player = beeperData.audioPlayback.player; player.audioOutput.muted = true;
      panel.chooseChat(1); panel.compose(); wait(10);
      if (data.cancel) keyClick(Qt.Key_Escape);
      beeperData.respond("download", {srcURL: silentAudio()}); wait(20);
      if (data.cancel) { verify(!beeperData.audioPlayback.playWhenReady); verify(player.playbackState !== MediaPlayer.PlayingState); }
      else tryCompare(player, "playbackState", MediaPlayer.PlayingState);
    }
    function test_space_opens_photo_without_a_header_and_closes_it_again() {
      const photo = {type: "img", srcURL: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="480"><rect width="640" height="480" fill="blue"/></svg>')};
      selectAttachment(photo);
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "media");
      compare(panel.previewAttachment.srcURL, photo.srcURL);
      const photoView = findChild(panel.modalSurface, "beeperFullscreenPhoto");
      verify(photoView.expanded);
      compare(photoView.width, panel.width); compare(photoView.height, panel.height);
      verify(!findChild(panel, "beeperModalSurface").visible);
      const image = findChild(photoView, "beeperMediaImage");
      tryCompare(image, "status", Image.Ready);
      fuzzyCompare(image.paintedHeight, panel.height, 0.5);
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "");
      compare(panel.selectedMessage.id, "media-message");
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "media");
      keyClick(Qt.Key_Escape); tryCompare(panel, "modal", "");
      compare(panel.selectedMessage.id, "media-message");
      keyClick(Qt.Key_Return); keyClick(Qt.Key_Space);
      compare(panel.composer.text, " "); compare(panel.modal, "");
    }
    function picture(color) {
      return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48"><rect width="64" height="48" fill="' + color + '"/></svg>');
    }
    function gallery() {
      const message = (id, index, extra) => Object.assign({id: id, chatID: "chat-a", senderName: "Contact",
        timestamp: new Date(1700000000000 + index * 60000).toISOString()}, extra);
      return [
        message("photo-a", 0, {attachments: [{id: "a", type: "img", srcURL: picture("red")}]}),
        message("text", 1, {text: "No attachment"}),
        message("video", 2, {attachments: [{id: "v", type: "video", srcURL: "mxc://preview/video"}]}),
        message("album", 3, {attachments: [{id: "b", type: "img", srcURL: picture("green")},
          {id: "c", type: "img", isGif: true, srcURL: "mxc://preview/gif"}]}),
        message("photo-d", 4, {attachments: [{id: "d", type: "img", fileName: "Plage.jpg", mimeType: "image/jpeg", srcURL: picture("yellow")}]})
      ];
    }
    function openFromMessage(index) {
      waitForHistory();
      panel.messageIndex = index; wait(20);
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "media");
    }
    function test_photo_viewer_h_l_walk_photos_and_gifs_but_not_videos() {
      beeperData.messages = gallery();
      openFromMessage(3);
      compare(panel.previewAttachment.id, "b");
      keyClick(Qt.Key_L); compare(panel.previewAttachment.id, "c"); compare(panel.selectedMessage.id, "album");
      keyClick(Qt.Key_L); compare(panel.previewAttachment.id, "d"); compare(panel.selectedMessage.id, "photo-d");
      keyClick(Qt.Key_L); compare(panel.previewAttachment.id, "d", "The newest photo stays shown");
      for (const id of ["c", "b", "a"]) { keyClick(Qt.Key_H); compare(panel.previewAttachment.id, id); }
      compare(panel.selectedMessage.id, "photo-a", "The video and the text message are skipped");
      keyClick(Qt.Key_H); compare(panel.previewAttachment.id, "a");
      compare(pending("messages").length, 0, "No older page exists");
      compare(panel.modal, "media");
      keyClick(Qt.Key_Escape); tryCompare(panel, "modal", "");
      compare(panel.selectedMessage.id, "photo-a", "Closing returns to the photo shown last");
    }
    function test_photo_viewer_h_loads_older_pages_at_the_oldest_photo() {
      const messages = gallery();
      beeperData.messages = messages.slice(3);
      beeperData.oldestCursor = "older"; beeperData.hasOlderMessages = true;
      openFromMessage(0);
      compare(panel.previewAttachment.id, "b");
      keyClick(Qt.Key_H);
      compare(pending("messages").length, 1);
      compare(pending("messages")[0].params.cursor, "older");
      compare(panel.previewAttachment.id, "b", "The photo stays until the older page arrives");
      beeperData.respond("messages", {items: messages.slice(0, 3), hasMore: false});
      tryVerify(() => panel.previewAttachment.id === "a");
      compare(panel.selectedMessage.id, "photo-a");
      keyClick(Qt.Key_Escape); tryCompare(panel, "modal", "");
    }
    function test_enter_saves_the_viewed_media_without_closing() {
      beeperData.messages = gallery();
      openFromMessage(4);
      const notice = findChild(panel.modalSurface, "beeperViewerNoticeText");
      keyClick(Qt.Key_Return);
      compare(panel.modal, "media", "Enter keeps the photo open");
      compare(pending("saveAttachment").length, 1);
      compare(pending("saveAttachment")[0].params, {url: picture("yellow"), fileName: "Plage.jpg", mimeType: "image/jpeg"});
      compare(notice.text, "Saving…");
      keyClick(Qt.Key_Return);
      compare(pending("saveAttachment").length, 1, "One save at a time");
      beeperData.respond("saveAttachment", {path: "/home/user/Téléchargements/Plage (2).jpg", name: "Plage (2).jpg"});
      compare(notice.text, "Saved to Téléchargements · Plage (2).jpg");
      verify(!panel.modalSurface.noticeFailed);
      keyClick(Qt.Key_Return);
      beeperData.respond("saveAttachment", null, {code: "save_failed", message: "Could not write the file."});
      compare(notice.text, "Could not write the file.");
      verify(panel.modalSurface.noticeFailed, "Failures use the error color");
      keyClick(Qt.Key_Escape); tryCompare(panel, "modal", "");
    }
    function noticeText() { return findChild(panel, "beeperNoticeText").text; }
    function test_y_copies_the_whole_selected_message() {
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.selectedMessage.id, "message-7");
      keyClick(Qt.Key_Y);
      compare(fixture.copiedTexts, ["Message 7"]);
      compare(noticeText(), "Message copied");
      compare(panel.selectedMessage.id, "message-7", "Copying keeps the message selection");
      compare(panel.navigation, "messages");
    }
    function test_y_on_a_message_without_text_says_so() {
      selectAttachment({type: "img", srcURL: picture("red")});
      keyClick(Qt.Key_Y);
      compare(fixture.copiedTexts, []);
      compare(noticeText(), "This message has no text");
    }
    function selectRowText(index, from, to) {
      const row = findChild(panel, "beeperMessages").itemAtIndex(index);
      mouseMove(findChild(row, "messageBody"), 4, 4);
      tryVerify(() => findChild(row, "beeperMessageTextSelection") !== null);
      const layer = findChild(row, "beeperMessageTextSelection");
      tryVerify(() => layer.width === findChild(row, "messageBody").width && layer.implicitHeight > 0);
      const a = layer.positionToRectangle(from), b = layer.positionToRectangle(to);
      mousePress(layer, a.x + 1, a.y + a.height / 2);
      mouseMove(layer, b.x + 1, b.y + b.height / 2);
      mouseRelease(layer, b.x + 1, b.y + b.height / 2);
      return row;
    }
    function test_mouse_selection_copies_with_y_or_ctrl_c_and_escape_clears_it() {
      waitForHistory();
      selectRowText(7, 0, 7);
      compare(panel.selectedText, "Message");
      keyClick(Qt.Key_C, Qt.ControlModifier);
      compare(fixture.copiedTexts, ["Message"]);
      compare(panel.selectedText, "Message", "Ctrl+C keeps the selection");
      keyClick(Qt.Key_Y);
      compare(fixture.copiedTexts, ["Message", "Message"]);
      compare(panel.selectedText, "", "y clears the selection, like a Vim yank");
      compare(noticeText(), "Selection copied");
      selectRowText(7, 8, 9);
      compare(panel.selectedText, "7");
      keyClick(Qt.Key_Escape);
      compare(panel.selectedText, "", "Escape first clears the selection");
      compare(closeSpy.count, 0); verify(panel.active);
    }
    function test_selecting_in_another_message_replaces_the_previous_selection() {
      waitForHistory();
      const first = selectRowText(7, 0, 7);
      selectRowText(6, 8, 9);
      compare(first.selectedText, "");
      compare(panel.selectedText, "6");
      keyClick(Qt.Key_Y);
      compare(fixture.copiedTexts, ["6"]);
    }
    function test_space_starts_audio_after_download_finishes() {
      const media = selectAttachment({type: "audio", srcURL: "mxc://preview/voice", duration: 2});
      compare(pending("download").length, 0, "Audio is downloaded by the persistent player on demand");
      const player = findChild(media, "beeperMediaPlayer"); player.audioOutput.muted = true;
      keyClick(Qt.Key_Space); tryCompare(media, "playWhenReady", true);
      compare(pending("download").length, 1);
      beeperData.respond("download", {srcURL: silentAudio()});
      tryCompare(player, "playbackState", MediaPlayer.PlayingState);
      keyClick(Qt.Key_Space); tryCompare(player, "playbackState", MediaPlayer.PausedState);
    }
    function test_fullscreen_photo_waits_for_download_without_a_stale_error() {
      selectAttachment({type: "img", srcURL: "mxc://preview/photo"});
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "media");
      const photo = findChild(panel.modalSurface, "beeperFullscreenPhoto");
      verify(photo.downloading); compare(photo.errorText, "");
      const source = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="480"><rect width="640" height="480" fill="blue"/></svg>');
      while (pending("download").length) beeperData.respond("download", {srcURL: source});
      tryCompare(findChild(photo, "beeperMediaImage"), "status", Image.Ready);
      compare(photo.errorText, "");
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "");
    }
    function test_second_space_cancels_audio_while_downloading() {
      const media = selectAttachment({type: "audio", srcURL: "mxc://preview/voice", duration: 2});
      const player = findChild(media, "beeperMediaPlayer"); player.audioOutput.muted = true;
      keyClick(Qt.Key_Space); tryCompare(media, "playWhenReady", true);
      keyClick(Qt.Key_Space); tryCompare(media, "playWhenReady", false);
      beeperData.respond("download", {srcURL: silentAudio()}); wait(100);
      compare(player.playbackState, MediaPlayer.StoppedState);
    }
  }
}
