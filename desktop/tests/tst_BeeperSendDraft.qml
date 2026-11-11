import QtQuick
import QtTest
import Quickshell

// Delayed send/draft replies with real keyboard input. No account is contacted.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  Window { id: window; width: 1280; height: 900; visible: true }
  TestResult { id: results }
  TestCase {
    name: "BeeperSendDraft"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function pending(method) { return beeperData.requests.filter(request => request.method === method); }
    function type(text) { panel.composer.insert(panel.composer.cursorPosition, text); }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {deferDrafts: true});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true});
      beeperData.replaceChats([{id: "first", title: "First", unreadCount: 2}, {id: "other", title: "Other"}]);
      panel.chooseChat(0); beeperData.respond("getDraft", {});
      beeperData.respond("messages", {items: [{id: "incoming", chatID: "first", text: "Hello", timestamp: "2026-09-26T10:00:00Z"}], hasMore: false});
      tryCompare(panel, "restoringView", false); panel.compose(); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperSendDraft: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function expandComposer() {
      panel.compose();
      keyClick(Qt.Key_Space, Qt.ControlModifier);
      tryCompare(panel, "composerExpanded", true);
      tryCompare(panel, "composerExpansion", 1);
      const surface = findChild(panel, "beeperComposerSurface");
      tryVerify(() => surface.height > panel.height * 0.7);
      return surface;
    }
    function test_confirmed_send_collapses_without_touching_the_next_draft() {
      type("First message");
      const surface = expandComposer();
      keyClick(Qt.Key_Return);
      verify(beeperData.sending); verify(panel.composerExpanded);
      type("Next draft"); panel.composer.select(0, 4);
      beeperData.respond("send", {});
      compare(panel.composerExpanded, false);
      tryCompare(panel, "composerExpansion", 0);
      tryVerify(() => surface.height < 100);
      compare(beeperData.draftText, "Next draft");
      compare(panel.composer.selectedText, "Next");
      verify(panel.composer.activeFocus);
    }
    function test_failed_send_keeps_expanded_editor_and_recovers_the_text() {
      type("Keep this message");
      const surface = expandComposer();
      keyClick(Qt.Key_Return);
      beeperData.respond("send", null, {message: "Sending failed"});
      wait(300);
      verify(panel.composerExpanded); compare(panel.composerExpansion, 1);
      verify(surface.height > panel.height * 0.65);
      compare(beeperData.draftText, "Keep this message");
      compare(panel.composer.text, "Keep this message");
    }
    function test_late_send_from_another_chat_does_not_collapse_current_editor() {
      type("First chat"); expandComposer(); keyClick(Qt.Key_Return);
      beeperData.selectChat("other");
      beeperData.respond("getDraft", {});
      beeperData.respond("messages", {items: [], hasMore: false});
      tryCompare(panel, "restoringView", false);
      panel.compose(); type("Other chat draft"); expandComposer();
      beeperData.respond("send", {});
      verify(panel.composerExpanded); compare(panel.composerExpansion, 1);
      compare(beeperData.draftText, "Other chat draft");
    }
    function test_successful_edit_restores_compact_editor() {
      panel.editMessageID = "incoming"; panel.editText = "Edited text";
      const surface = expandComposer();
      keyClick(Qt.Key_Return);
      tryCompare(panel, "editMessageID", "");
      tryCompare(panel, "composerExpansion", 0);
      verify(!panel.composerExpanded);
      tryVerify(() => surface.height < 100);
    }
    function test_enter_clears_immediately_and_late_success_keeps_the_next_text_and_cursor() {
      type("Premier message 🌿"); keyClick(Qt.Key_Return);
      verify(beeperData.sending); compare(pending("send").length, 1);
      compare(pending("send")[0].params.text, "Premier message 🌿");
      compare(panel.composer.text, ""); compare(panel.composer.cursorPosition, 0); verify(panel.composer.activeFocus);
      keyClick(Qt.Key_S); type("uivant é🙂");
      compare(panel.composer.text, "suivant é🙂");
      panel.composer.cursorPosition = 3;
      beeperData.respond("send", {pendingMessageID: "accepted"});
      compare(panel.composer.text, "suivant é🙂"); compare(beeperData.draftText, "suivant é🙂");
      compare(panel.composer.cursorPosition, 3); verify(panel.composer.activeFocus);
      compare(pending("read")[0].params.messageID, "incoming");
    }
    function test_forward_preserves_both_drafts_and_late_destination_draft() {
      type("Source draft"); beeperData.replyToMessageID = "incoming";
      const source = {id: "incoming", text: "Forwarded text", linkedMessageID: "old-reply"};
      verify(beeperData.forwardMessage(source, "other"));
      panel.chooseChat(1);
      beeperData.respond("getDraft", {text: "Destination draft", replyToMessageID: "destination-reply"});
      compare(pending("send")[0].params.text, "Forwarded text");
      compare(pending("send")[0].params.replyToMessageID, "");
      verify(!beeperData.forwardMessage(source, "other"));
      beeperData.respond("send", {});
      compare(beeperData.draftText, "Destination draft"); compare(beeperData.replyToMessageID, "destination-reply");
      compare(beeperData.localDrafts.first.text, "Source draft");
      compare(beeperData.localDrafts.first.replyToMessageID, "incoming");
      compare(pending("read").length, 0); compare(beeperData.recoverableDrafts.length, 0);
    }
    function forwardAlbum() {
      beeperData.deferAttachments = true; beeperData.deferImageEdits = true;
      verify(beeperData.forwardMessage({text: "Caption", attachments: [
        {srcURL: "mxc://example/photo", type: "img", fileName: "photo.png", mimeType: "image/png"},
        {srcURL: "file:///fixture/voice.ogg", isVoiceNote: true, mimeType: "audio/ogg"}
      ]}, "other"));
      compare(pending("send").length, 0);
      compare(pending("download")[0].params.url, "mxc://example/photo");
      beeperData.respond("download", {srcURL: "file:///fixture/cached-photo"});
      compare(pending("stageAttachment")[0].params.type, "image");
      beeperData.respond("stageAttachment", {path: "/fixture/staged-photo", type: "image", fileName: "cached-photo"});
      compare(pending("send").length, 0);
      compare(pending("stageAttachment")[0].params.type, "voice-note");
    }
    function test_forward_prepares_all_media_and_sends_in_order_without_touching_draft() {
      type("Keep this draft"); forwardAlbum();
      beeperData.respond("stageAttachment", {path: "/fixture/staged-voice", type: "voice-note"});
      const first = pending("send")[0].params;
      compare(first.chatID, "other"); compare(first.text, "Caption");
      compare(first.attachment.fileName, "photo.png"); compare(first.attachment.mimeType, "image/png");
      beeperData.respond("send", {});
      const second = pending("send")[0].params;
      compare(second.text, ""); compare(second.attachment.type, "voice-note");
      beeperData.respond("send", {});
      verify(!beeperData.sending); compare(beeperData.draftText, "Keep this draft");
      compare(pending("discardAttachment").map(request => request.params.path), ["/fixture/staged-photo", "/fixture/staged-voice"]);
    }
    function test_forward_preparation_failure_sends_nothing_and_cleans_private_copies() {
      forwardAlbum();
      beeperData.respond("stageAttachment", null, {message: "File missing"});
      verify(!beeperData.sending); compare(pending("send").length, 0);
      compare(beeperData.lastError, "File missing");
      compare(pending("discardAttachment")[0].params.path, "/fixture/staged-photo");
    }
    function test_forward_partial_failure_reports_progress_without_retrying() {
      forwardAlbum();
      beeperData.respond("stageAttachment", {path: "/fixture/staged-voice", type: "voice-note"});
      beeperData.respond("send", {});
      beeperData.respond("send", null, {message: "Sending was not confirmed. Check the conversation."});
      verify(!beeperData.sending); compare(pending("send").length, 0);
      verify(beeperData.lastError.includes("1 attachment(s) already forwarded"));
      verify(beeperData.lastError.includes("Check the conversation"));
    }
    function test_forward_stops_if_destination_becomes_readonly_during_preparation() {
      forwardAlbum();
      beeperData.replaceChats([{id: "first"}, {id: "other", isReadOnly: true}]);
      beeperData.respond("stageAttachment", {path: "/fixture/staged-voice", type: "voice-note"});
      verify(!beeperData.sending); compare(pending("send").length, 0);
      compare(pending("discardAttachment").length, 2);
      compare(beeperData.lastError, "Conversation unavailable.");
    }
    function test_forward_rejects_empty_deleted_readonly_and_offline_messages() {
      verify(!beeperData.forwardMessage({}, "other"));
      verify(!beeperData.forwardMessage({text: "Deleted", isDeleted: true}, "other"));
      verify(!beeperData.forwardMessage({text: "Hello"}, "missing"));
      beeperData.replaceChats([{id: "first"}, {id: "other", isReadOnly: true}]);
      verify(!beeperData.forwardMessage({text: "Hello"}, "other"));
      beeperData.state = "offline";
      verify(!beeperData.forwardMessage({text: "Hello"}, "first"));
      compare(pending("send").length, 0);
    }
    function test_identical_next_message_is_not_erased_by_the_previous_confirmation() {
      type("ok"); keyClick(Qt.Key_Return); type("ok");
      beeperData.respond("send", {});
      compare(panel.composer.text, "ok"); compare(beeperData.draftText, "ok");
      keyClick(Qt.Key_Return); compare(pending("send").length, 1);
      compare(pending("send")[0].params.text, "ok"); compare(panel.composer.text, "");
    }
    function test_pending_send_keeps_next_input_but_does_not_duplicate_submission() {
      type("First"); keyClick(Qt.Key_Return); type("Second");
      keyClick(Qt.Key_Return); keyClick(Qt.Key_Return);
      compare(pending("send").length, 1); compare(panel.composer.text, "Second");
      beeperData.respond("send", {}); keyClick(Qt.Key_Return);
      compare(pending("send").length, 1); compare(pending("send")[0].params.text, "Second");
    }
    function test_attachment_and_reply_move_with_the_sent_message_not_the_next_draft() {
      const oldAttachment = {path: "/fixture/first.txt", fileName: "first.txt", type: "unknown"};
      beeperData.draftAttachments = [oldAttachment]; beeperData.replyToMessageID = "incoming";
      type("With a picture"); keyClick(Qt.Key_Return);
      const sent = pending("send")[0].params;
      compare(sent.attachment.path, oldAttachment.path); compare(sent.replyToMessageID, "incoming");
      compare(beeperData.draftAttachment, null); compare(beeperData.replyToMessageID, "");
      type("Next"); beeperData.draftAttachments = [{path: "/fixture/next.txt", fileName: "next.txt", type: "unknown"}];
      beeperData.replyToMessageID = "another-message";
      beeperData.respond("send", {});
      compare(panel.composer.text, "Next"); compare(beeperData.draftAttachment.path, "/fixture/next.txt");
      compare(beeperData.replyToMessageID, "another-message");
    }
    function files() { return ["one", "two", "three"].map(name => ({path: "/fixture/" + name + ".txt", fileName: name + ".txt", type: "file"})); }
    function flushSavedProgress() {
      while (pending("saveDraft").length) beeperData.respond("saveDraft", {});
    }
    function test_multiple_files_send_in_order_with_text_only_once() {
      beeperData.draftAttachments = files(); beeperData.replyToMessageID = "incoming";
      type("The documents"); keyClick(Qt.Key_Return);
      compare(beeperData.draftAttachments, []); verify(beeperData.sending);
      for (let i = 0; i < 3; ++i) {
        compare(pending("send").length, 1);
        const payload = pending("send")[0].params;
        compare(payload.attachment.path, files()[i].path);
        compare(payload.text, i === 0 ? "The documents" : "");
        compare(payload.replyToMessageID, i === 0 ? "incoming" : "");
        beeperData.respond("send", {pendingMessageID: "accepted-" + i});
        if (i < 2) {
          verify(beeperData.sending); compare(pending("send").length, 0);
          compare(beeperData.recoverableDrafts[0].attachments.length, 2 - i);
          flushSavedProgress();
        }
      }
      verify(!beeperData.sending); compare(beeperData.recoverableDrafts, []);
      compare(pending("send").length, 0);
    }
    function test_partial_failure_recovers_only_unsent_files_data() {
      return [{tag: "empty_draft", next: false}, {tag: "new_draft", next: true}];
    }
    function test_partial_failure_recovers_only_unsent_files(data) {
      beeperData.draftAttachments = files(); type("Sent caption"); keyClick(Qt.Key_Return);
      beeperData.respond("send", {}); flushSavedProgress();
      if (data.next) type("My next message");
      beeperData.respond("send", null, {code: "send_uncertain", message: "Check whether the second file was sent"});
      verify(!beeperData.sending); compare(pending("send").length, 0);
      const remaining = data.next ? beeperData.recoverableDrafts[0] : beeperData.draftSnapshot();
      compare(remaining.attachments.map(file => file.path), files().slice(1).map(file => file.path));
      compare(remaining.text, "");
      if (data.next) { compare(panel.composer.text, "My next message"); compare(beeperData.draftAttachments, []); }
    }
    function test_failed_progress_save_stops_before_next_file() {
      beeperData.draftAttachments = files(); keyClick(Qt.Key_Return);
      flushSavedProgress(); beeperData.respond("send", {});
      beeperData.respond("saveDraft", null, {message: "Disk unavailable"});
      verify(!beeperData.sending); compare(pending("send").length, 0);
      compare(beeperData.draftAttachments.map(file => file.path), files().slice(1).map(file => file.path));
    }
    function test_multiple_files_survive_switching_chats_and_old_drafts_still_load() {
      beeperData.draftAttachments = files(); type("Keep all files");
      panel.chooseChat(1); beeperData.respond("getDraft", {attachment: {path: "/fixture/legacy.txt", type: "file"}});
      compare(beeperData.draftAttachments.length, 1); compare(beeperData.draftAttachment.path, "/fixture/legacy.txt");
      panel.chooseChat(0);
      compare(beeperData.draftAttachments.map(file => file.path), files().map(file => file.path));
      beeperData.respond("getDraft", {text: "Keep all files", attachments: files()});
      compare(beeperData.draftAttachments.length, 3);
      compare(beeperData.draftText, "Keep all files");
    }
    function test_failed_send_restores_the_original_only_if_no_new_draft_exists() {
      type("Keep this on failure"); beeperData.replyToMessageID = "incoming";
      keyClick(Qt.Key_Return); compare(panel.composer.text, "");
      beeperData.respond("send", null, {message: "Connection interrupted"});
      compare(panel.composer.text, "Keep this on failure"); compare(beeperData.replyToMessageID, "incoming");
      compare(beeperData.recoverableDrafts.length, 0); verify(panel.composer.activeFocus);
      compare(pending("read").length, 0); compare(pending("send").length, 0);
    }
    function test_uncertain_send_keeps_both_drafts_separate_and_restore_swaps_without_sending() {
      type("Unconfirmed first message"); keyClick(Qt.Key_Return); type("New draft");
      beeperData.respond("send", null, {code: "send_uncertain", message: "Check the conversation before trying again"});
      compare(panel.composer.text, "New draft"); compare(beeperData.recoverableDrafts.length, 1);
      compare(beeperData.recoverableDrafts[0].text, "Unconfirmed first message");
      verify(findChild(panel, "beeperSavedSendDraft").visible);
      mouseClick(findChild(panel, "beeperRestoreSendDraft"));
      compare(panel.composer.text, "Unconfirmed first message"); verify(panel.composer.activeFocus);
      compare(beeperData.recoverableDrafts.length, 1); compare(beeperData.recoverableDrafts[0].text, "New draft");
      mouseClick(findChild(panel, "beeperRestoreSendDraft"));
      compare(panel.composer.text, "New draft"); compare(pending("send").length, 0); compare(pending("read").length, 0);
    }
    function test_submitted_snapshot_is_saved_before_send_and_success_only_removes_its_backup() {
      type("Durable original"); keyClick(Qt.Key_Return);
      const requests = beeperData.requests;
      const sendIndex = requests.findIndex(request => request.method === "send");
      const saveIndex = requests.findIndex(request => request.method === "saveDraft" && request.params.savedDrafts?.length);
      verify(saveIndex >= 0 && saveIndex < sendIndex);
      compare(requests[saveIndex].params.text, ""); compare(requests[saveIndex].params.savedDrafts[0].text, "Durable original");
      verify(!findChild(panel, "beeperSavedSendDraft").visible, "In-flight backup is not presented as a failure");
      type("Next draft"); beeperData.respond("send", {});
      const latest = pending("saveDraft").slice(-1)[0].params;
      compare(latest.text, "Next draft"); compare(latest.savedDrafts.length, 0);
    }
    function test_chat_switch_and_late_success_preserve_each_chats_next_draft() {
      type("Sent in first"); keyClick(Qt.Key_Return); type("First chat's next draft");
      beeperData.selectChat("other"); beeperData.respond("getDraft", {text: "Other draft"});
      beeperData.respond("messages", {items: [], hasMore: false}); panel.compose();
      beeperData.respond("send", {});
      compare(beeperData.currentChatID, "other"); compare(panel.composer.text, "Other draft");
      compare(beeperData.localDrafts.first.text, "First chat's next draft");
      compare(pending("read")[0].params.chatID, "first");
      const saved = pending("saveDraft").filter(request => request.params.chatID === "first").slice(-1)[0].params;
      compare(saved.text, "First chat's next draft"); compare(saved.savedDrafts.length, 0);
    }
    function test_late_failure_restores_only_the_original_conversation() {
      type("Restore in first"); keyClick(Qt.Key_Return);
      beeperData.selectChat("other"); beeperData.respond("getDraft", {text: "Leave other alone"});
      beeperData.respond("messages", {items: [], hasMore: false}); panel.compose();
      beeperData.respond("send", null, {message: "Not sent"});
      compare(panel.composer.text, "Leave other alone"); compare(beeperData.localDrafts.first.text, "Restore in first");
      compare(pending("read").length, 0);
    }
    function test_stale_draft_response_cannot_resurrect_an_accepted_message_or_its_backup() {
      beeperData.selectChat("other"); beeperData.respond("messages", {items: [], hasMore: false}); panel.compose();
      type("Send before draft lookup returns"); keyClick(Qt.Key_Return);
      const backup = beeperData.recoverableDrafts[0];
      type("Next"); beeperData.respond("send", {});
      beeperData.respond("getDraft", {text: "Send before draft lookup returns", savedDrafts: [backup]});
      compare(panel.composer.text, "Next"); compare(beeperData.recoverableDrafts.length, 0);
    }
    function test_saved_backup_from_previous_session_is_recoverable_without_overwriting_new_typing() {
      beeperData.selectChat("other"); beeperData.respond("messages", {items: [], hasMore: false}); panel.compose();
      type("Already typing");
      beeperData.respond("getDraft", {text: "Stale editor", savedDrafts: [{id: "previous-session", text: "Unconfirmed from before", replyToMessageID: "original"}]});
      compare(panel.composer.text, "Already typing"); compare(beeperData.recoverableDrafts.length, 1);
      compare(beeperData.recoverableDrafts[0].text, "Unconfirmed from before");
      const latest = pending("saveDraft").slice(-1)[0].params;
      compare(latest.text, "Already typing"); compare(latest.savedDrafts.length, 1);
      compare(pending("send").length, 0);
    }
  }
}
