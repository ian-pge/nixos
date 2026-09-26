import QtQuick
import QtTest
import QtMultimedia
import Quickshell

// Real keyboard routing with an in-memory transport: no reactions are sent.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
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
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 0); wait(20);
      return findChild(findChild(panel, "beeperMessages").itemAtIndex(0), "beeperMedia");
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true});
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
        {tag: "default", network: "WhatsApp", emoji: ["😂", "💜", "🔥", "💯", "🤡"]},
        {tag: "telegram_in_all", network: "Telegram", emoji: ["🤣", "❤️", "🔥", "💯", "🤡"]}
      ];
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
    }
    function test_ctrl_navigation_preserves_draft_and_escape_returns_to_chats() {
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.messageIndex, 7);
      keyClick(Qt.Key_Return); verify(panel.composer.activeFocus);
      for (let key = Qt.Key_1; key <= Qt.Key_5; ++key) keyClick(key);
      compare(panel.composer.text, "12345"); compare(pending("react").length, 0);
      keyClick(Qt.Key_K, Qt.ControlModifier);
      compare(panel.messageIndex, 7); verify(!panel.composer.activeFocus);
      keyClick(Qt.Key_K, Qt.ControlModifier);
      compare(panel.messageIndex, 6); verify(!panel.composer.activeFocus);
      compare(beeperData.draftText, "12345");
      keyClick(Qt.Key_Escape); compare(panel.navigation, "chats");
      compare(panel.messageIndex, -1); verify(!findChild(panel, "beeperMessages").itemAtIndex(6).selected);
      keyClick(Qt.Key_J, Qt.ControlModifier);
      compare(panel.messageIndex, 7); compare(beeperData.currentChatID, "chat-a");
      keyClick(Qt.Key_Escape); keyClick(Qt.Key_J);
      compare(beeperData.currentChatID, "chat-b"); compare(panel.messageIndex, -1);
      keyClick(Qt.Key_K); compare(beeperData.currentChatID, "chat-a");
      compare(beeperData.localDrafts["chat-a"].text, "12345");
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
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_2);
      compare(pending("react")[0].params.reactionKey, "😂"); verify(pending("react")[0].params.remove);
      beeperData.respond("react", {});
      compare(pending("react")[0].params.reactionKey, "💜"); verify(!pending("react")[0].params.remove);
      beeperData.respond("react", {});
      const updated = beeperData.messages[7];
      compare(updated.reactions.length, 2);
      compare(updated.reactions.find(reaction => reaction.participantID === "contact").id, "theirs");
      compare(updated.reactions.find(reaction => reaction.participantID === "self").reactionKey, "💜");
      beeperData.respond("message", updated);
      keyClick(Qt.Key_2);
      compare(pending("react")[0].params.reactionKey, "💜"); verify(pending("react")[0].params.remove);
      beeperData.respond("react", {});
      compare(beeperData.messages[7].reactions.length, 1);
      compare(beeperData.messages[7].reactions[0].id, "theirs");
      compare(pending("react").length, 0);
    }
    function test_fast_reaction_changes_are_serialized_and_last_choice_wins() {
      keyClick(Qt.Key_K, Qt.ControlModifier);
      keyClick(Qt.Key_1); keyClick(Qt.Key_2); keyClick(Qt.Key_3);
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
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_1);
      beeperData.respond("react", {});
      const stale = beeperData.messages[7];
      compare(pending("message").length, 1);
      keyClick(Qt.Key_2); beeperData.respond("react", {}); beeperData.respond("react", {});
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
      compare(panel.messageIndex, 0); keyClick(Qt.Key_4);
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
      compare(panel.selectedMessage, null);
      keyClick(Qt.Key_K, Qt.ControlModifier); compare(panel.selectedMessage.id, "sent");
    }
    function test_refresh_cannot_restore_selection_after_returning_to_sidebar() {
      keyClick(Qt.Key_K, Qt.ControlModifier); panel.moveMessageSelection(-3);
      beeperData.messagesUpdating();
      panel.focusNavigation();
      beeperData.messagesLoaded(false);
      compare(panel.selectedMessage, null);
      keyClick(Qt.Key_L); compare(panel.messageIndex, 7);
    }
    function test_escape_cancels_reply_or_edit_before_leaving_composer_data() {
      return [{tag: "reply", edit: false}, {tag: "edit", edit: true}];
    }
    function test_escape_cancels_reply_or_edit_before_leaving_composer(data) {
      beeperData.messages = [{id: "original", chatID: "chat-a", isSender: true, text: "Message original"}];
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
      keyClick(Qt.Key_K, Qt.ControlModifier); keyClick(Qt.Key_5);
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
      keyClick(Qt.Key_1); compare(panel.searchField.text, "1"); compare(pending("react").length, 0);
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
      keyClick(Qt.Key_Space); compare(panel.modal, "");
      compare(panel.selectedMessage.id, "media-message");
      keyClick(Qt.Key_Space); tryCompare(panel, "modal", "media");
      keyClick(Qt.Key_Escape); compare(panel.modal, "");
      compare(panel.selectedMessage.id, "media-message");
      keyClick(Qt.Key_Return); keyClick(Qt.Key_Space);
      compare(panel.composer.text, " "); compare(panel.modal, "");
    }
    function test_space_starts_audio_after_download_finishes() {
      const media = selectAttachment({type: "audio", srcURL: "mxc://preview/voice", duration: 2});
      compare(pending("download").length, 1);
      const player = findChild(media, "beeperMediaPlayer"); player.audioOutput.muted = true;
      keyClick(Qt.Key_Space); tryCompare(media, "playWhenReady", true);
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
      keyClick(Qt.Key_Space); compare(panel.modal, "");
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
