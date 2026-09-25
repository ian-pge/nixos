import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var beeperData: null
  property var format: null
  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") { Qt.exit(1); return; }
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../BeeperData.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    beeperData = component.createObject(fixture, {demo: true});
    format = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../components/BeeperFormat.js" as F; QtObject { property var library: F }', fixture).library;
  }
  TestResult { id: results }
  TestCase {
    name: "BeeperData"
    when: beeperData !== null && beeperData.demoMessages.studio !== undefined
    function cleanupTestCase() { console.log("BeeperData: " + results.passCount + " passed, " + results.failCount + " failed"); Qt.exit(results.failCount ? 1 : 0); }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function test_switch_discards_stale_async_messages() {
      beeperData.selectChat("lea"); beeperData.selectChat("studio"); beeperData.selectChat("alex");
      wait(20); compare(beeperData.currentChatID, "alex"); compare(beeperData.messages.length, 0);
    }
    function test_event_during_inflight_request_gets_trailing_refresh() {
      beeperData.selectChat("studio"); wait(20);
      beeperData.loadMessages(false);
      beeperData.demoMessages.studio = beeperData.demoMessages.studio.concat([{id: "trailing", chatID: "studio", text: "Arrivé pendant le chargement", timestamp: new Date().toISOString()}]);
      beeperData.loadMessages(false);
      verify(beeperData.trailingMessagesRefresh);
      wait(30);
      verify(beeperData.messages.some(message => message.id === "trailing"));
      verify(!beeperData.trailingMessagesRefresh);
    }
    function test_refresh_preserves_loaded_chat_pages_and_cursor() {
      const tail = {id: "older-page-chat", title: "Ancienne conversation"};
      beeperData.chatsInitialized = true; beeperData.chatsCursor = "oldest-page-cursor"; beeperData.hasMoreChats = false;
      beeperData.refreshChats(false);
      beeperData.chats = beeperData.chats.concat([tail]);
      wait(20);
      verify(beeperData.chats.some(chat => chat.id === tail.id));
      compare(beeperData.chatsCursor, "oldest-page-cursor"); verify(!beeperData.hasMoreChats);
      beeperData.acceptLine(JSON.stringify({event: "chatsDeleted", data: {ids: [tail.id]}}));
      verify(!beeperData.chats.some(chat => chat.id === tail.id));
    }
    function test_send_then_switch_clears_original_chat_draft() {
      beeperData.selectChat("studio"); wait(0);
      beeperData.draftText = "Envoyé avant de changer de conversation";
      beeperData.sendMessage(); beeperData.selectChat("lea");
      wait(20); beeperData.selectChat("studio"); wait(20);
      compare(beeperData.draftText, "");
    }
    function test_edit_while_send_pending_survives_chat_switch() {
      beeperData.selectChat("studio"); wait(0);
      beeperData.draftText = "Message à envoyer";
      beeperData.sendMessage(); beeperData.draftText = "Nouveau brouillon"; beeperData.selectChat("lea");
      wait(20); beeperData.selectChat("studio"); wait(20);
      compare(beeperData.draftText, "Nouveau brouillon");
    }
    function test_late_draft_does_not_overwrite_new_typing() {
      beeperData.selectChat("lea"); beeperData.draftText = "Nouvelle saisie avant la réponse";
      wait(20); compare(beeperData.draftText, "Nouvelle saisie avant la réponse");
    }
    function test_dedup_and_chronology_preserve_equal_timestamp_order() {
      const before = [{id: "a", timestamp: "2026-09-24T10:00:00Z", text: "old"}, {id: "b", timestamp: "2026-09-24T10:00:00Z"}];
      const after = [{id: "a", timestamp: "2026-09-24T10:00:00Z", text: "edited"}, {id: "c", timestamp: "2026-09-24T09:00:00Z"}];
      const rows = fixture.format.mergeMessages(before, after);
      compare(rows.length, 3); compare(rows[0].id, "c"); compare(rows[1].id, "a"); compare(rows[1].text, "edited"); compare(rows[2].id, "b");
    }
    function test_media_types_use_official_voice_note_and_mime() {
      compare(fixture.format.attachmentType({type: "voice-note"}), "audio");
      compare(fixture.format.attachmentType({type: "video", mimeType: "video/mp4", isGif: true}), "video");
      compare(fixture.format.attachmentType({mimeType: "image/gif"}), "gif");
      compare(fixture.format.attachmentType({type: "img"}), "image");
      compare(fixture.format.attachmentType({type: "unknown", isVoiceNote: true}), "audio");
      compare(fixture.format.attachmentType({type: "unknown", isSticker: true}), "image");
      compare(fixture.format.attachmentType({type: "img", isGif: true}), "gif");
      compare(fixture.format.attachmentSource({id: "mxc://beeper/id"}), "mxc://beeper/id");
    }
    function test_deletion_events_remove_cached_messages_and_warning_visible() {
      beeperData.selectChat("studio"); wait(20);
      const id = beeperData.messages[0].id;
      beeperData.acceptLine(JSON.stringify({event: "messagesDeleted", data: {chatID: "studio", ids: [id]}}));
      verify(!beeperData.messages.some(message => message.id === id));
      beeperData.loadMessages(false); wait(20);
      verify(!beeperData.messages.some(message => message.id === id));
      beeperData.acceptLine(JSON.stringify({event: "sendFailed", data: {message: "Message non transmis"}}));
      compare(beeperData.lastError, "Message non transmis");
    }
    function test_safe_plain_body_and_capability_limits() {
      compare(fixture.format.text({text: "<b>Texte</b>", plainText: "Texte"}), "Texte");
      verify(!fixture.format.supports({capabilities: {edit: 0}}, "edit"));
      verify(!fixture.format.supports({isReadOnly: true}, "reply"));
      verify(fixture.format.supports({capabilities: {reply: 2}}, "reply"));
      verify(!fixture.format.supports({capabilities: {edit: 2, editMaxAge: 1}}, "edit", {timestamp: "2020-01-01T00:00:00Z"}));
      compare(fixture.format.links({links: [{url: "javascript:alert(1)"}, {url: "https://example.test"}]}).length, 1);
    }
    function test_group_colors_follow_identity_and_survive_history_loading() {
      beeperData.selectChat("studio"); wait(20);
      const original = Object.assign({}, beeperData.senderColors);
      const added = [];
      for (let i = 0; i < 20; ++i) added.push({id: "color-message-" + i,
        chatID: "studio", senderID: "color-person-" + i, senderName: "Même nom", text: "Bonjour"});
      beeperData.messages = added.concat(beeperData.messages);
      const colors = Object.values(beeperData.senderColors);
      compare(new Set(colors).size, colors.length);
      for (const id of Object.keys(original)) compare(beeperData.senderColors[id], original[id]);
      const author = beeperData.senderColors["color-person-0"];
      beeperData.messages = beeperData.messages.slice().reverse().concat([
        {id: "renamed", chatID: "studio", senderID: "color-person-0", senderName: "Nom modifié"}
      ]);
      compare(beeperData.senderColors["color-person-0"], author);
      beeperData.selectChat("lea"); wait(20); compare(Object.keys(beeperData.senderColors).length, 0);
      beeperData.selectChat("studio"); wait(20);
      compare(beeperData.senderColors["color-person-0"], author);
    }
    function test_status_revision_prevents_late_startup_response_from_resetting_connection() {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../BeeperData.qml");
      const data = component.createObject(fixture, {demo: true});
      data.applyStatus({state: "loading-token", revision: 1});
      verify(!data.tokenRequired);
      data.pending[999] = {method: "status", callback: (result, error) => data.applyStatus(result)};
      data.acceptLine(JSON.stringify({event: "status", data: {state: "connected", revision: 3}}));
      data.acceptLine(JSON.stringify({id: 999, result: {state: "needs-token", revision: 2}}));
      compare(data.state, "connected"); verify(!data.tokenRequired);
      data.applyStatus({state: "offline", revision: 4}); verify(!data.tokenRequired);
      data.applyStatus({state: "keyring-unavailable", revision: 5}); verify(!data.tokenRequired);
      data.applyStatus({state: "needs-token", revision: 6}); verify(data.tokenRequired);
      data.applyStatus({state: "invalid-token", revision: 7}); verify(data.tokenRequired);
      data.destroy();
    }
    function test_malformed_response_does_not_erase_chats() {
      const count = beeperData.chats.length;
      beeperData.acceptLine("not json"); compare(beeperData.chats.length, count); verify(!!beeperData.lastError);
    }
    function test_failed_send_preserves_draft() {
      beeperData.draftText = "Message à garder";
      beeperData.pending[123] = {method: "send", callback: (result, error) => { verify(!!error); }};
      beeperData.acceptLine(JSON.stringify({id: 123, error: {code: "uncertain", message: "Résultat incertain"}}));
      compare(beeperData.draftText, "Message à garder"); compare(beeperData.lastError, "Résultat incertain");
    }
  }
}
