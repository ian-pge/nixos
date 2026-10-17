import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var resolver: null
  property var format: null
  Component.onCompleted: format = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../features/messenger/BeeperFormat.js" as F; QtObject { property var library: F }', fixture).library
  QtObject {
    id: model
    property bool enabled: true
    property bool connected: true
    property bool demo: false
    property var chats: []
    property var requests: []
    function request(method, params, callback, quiet) {
      requests = requests.concat([{method: method, params: params, callback: callback, quiet: quiet}]);
    }
  }
  Window { id: window; visible: true; width: 200; height: 100 }
  TestResult { id: results }
  TestCase {
    name: "BeeperChatPreviews"
    when: window.visible && fixture.format !== null
    function init() {
      model.chats = []; model.requests = []; model.connected = true;
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperChatPreviews.qml");
      compare(component.status, Component.Ready, component.errorString());
      resolver = component.createObject(fixture, {beeperData: model}); verify(resolver !== null);
    }
    function cleanup() { resolver.destroy(); wait(0); }
    function cleanupTestCase() {
      console.log("BeeperChatPreviews: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function message(id, second, extra) {
      return Object.assign({id: id, timestamp: "2026-10-16T10:00:" + String(second).padStart(2, "0") + "Z"}, extra || {});
    }
    function chat(id = "chat", preview = {id: "latest"}) { return {id: id, type: "group", preview: preview}; }
    function respond(method, result, error = null) {
      tryVerify(() => model.requests.length > 0);
      const request = model.requests[0]; compare(request.method, method); verify(request.quiet);
      model.requests = model.requests.slice(1); request.callback(result, error);
    }
    function preview() { return fixture.format.preview(model.chats[0], resolver.entries); }
    function reaction(extra) {
      return message("reaction", 10, Object.assign({type: "REACTION", isHidden: true, senderID: "alice", senderName: "Alice", linkedMessageID: "parent"}, extra || {}));
    }
    function test_complete_previews_need_no_requests_and_media_have_specific_labels_data() {
      return [
        {tag: "text", value: {text: "Bonjour", senderName: "Alice"}, expected: "Alice: Bonjour"},
        {tag: "own", value: {text: "Salut", isSender: true}, expected: "You: Salut"},
        {tag: "photo", value: {plainText: "", attachments: [{type: "img"}]}, expected: "Photo"},
        {tag: "voice", value: {attachments: [{isVoiceNote: true}]}, expected: "Voice message"},
        {tag: "audio", value: {type: "AUDIO"}, expected: "Audio"},
        {tag: "video", value: {type: "VIDEO"}, expected: "Video"},
        {tag: "file", value: {attachments: [{type: "file", fileName: "report.pdf"}]}, expected: "report.pdf"},
        {tag: "sticker", value: {type: "STICKER"}, expected: "Sticker"},
        {tag: "caption", value: {plainText: "Caption", attachments: [{type: "img"}]}, expected: "Caption"}
      ];
    }
    function test_complete_previews_need_no_requests_and_media_have_specific_labels(data) {
      model.chats = [chat("chat", Object.assign({id: "latest"}, data.value))]; wait(0);
      compare(preview(), data.expected); compare(model.requests.length, 0);
    }
    function test_reaction_to_own_message_uses_correct_sender_and_is_cached() {
      const original = chat(); model.chats = [original];
      respond("messages", {items: [message("parent", 1, {text: "Sent", isSender: true, reactions: [
        {participantID: "other", reactionKey: "😂"}, {participantID: "alice", reactionKey: "❤️"}]}), reaction()]});
      compare(preview(), "Alice: Reacted ❤️ to your message");
      compare(model.chats[0].preview.id, "latest", "Read marker keeps the native API preview");
      model.chats = [Object.assign({}, original)]; wait(0);
      compare(model.requests.length, 0); compare(preview(), "Alice: Reacted ❤️ to your message");
    }
    function test_reaction_target_can_be_outside_the_loaded_page() {
      model.chats = [chat()]; respond("messages", {items: [reaction()]});
      compare(model.requests[0].params.messageID, "parent");
      respond("message", {isSender: true, reactions: [{participantID: "alice", reactionKey: "👍"}]});
      compare(preview(), "Alice: Reacted 👍 to your message");
    }
    function test_multiple_reactions_do_not_guess_which_emoji_was_latest() {
      model.chats = [chat()];
      respond("messages", {items: [reaction(), message("parent", 1, {isSender: true, reactions: [
        {participantID: "alice", reactionKey: "❤️"}, {participantID: "alice", reactionKey: "👍"}]} )]});
      compare(preview(), "Alice: Reacted to your message");
    }
    function test_irrelevant_events_fall_back_to_latest_visible_message_data() {
      return [
        {tag: "own reaction", event: {isSender: true}, parent: {isSender: true, reactions: [{participantID: "alice", reactionKey: "👍"}]}},
        {tag: "other target", event: {}, parent: {isSender: false, reactions: [{participantID: "alice", reactionKey: "👍"}]}},
        {tag: "removed reaction", event: {}, parent: {isSender: true, reactions: [{participantID: "other", reactionKey: "👍"}]}},
        {tag: "deleted reaction", event: {isDeleted: true}, parent: {isSender: true, reactions: [{participantID: "alice", reactionKey: "👍"}]}},
        {tag: "system event", event: {type: "NOTICE", text: "Internal event"}, parent: {}}
      ];
    }
    function test_irrelevant_events_fall_back_to_latest_visible_message(data) {
      model.chats = [chat()];
      respond("messages", {items: [reaction(data.event), message("photo", 5, {type: "IMAGE", senderName: "Bob"}),
        message("parent", 1, Object.assign({text: "Older"}, data.parent))]});
      compare(preview(), "Bob: Photo"); compare(model.requests.length, 0);
    }
    function test_latest_text_wins_over_older_reaction() {
      model.chats = [chat()];
      respond("messages", {items: [reaction(), message("text", 20, {text: "Latest answer", senderName: "Alice"})]});
      compare(preview(), "Alice: Latest answer"); compare(model.requests.length, 0);
    }
    function test_stale_response_cannot_replace_new_activity() {
      model.chats = [chat()]; tryVerify(() => model.requests.length === 1);
      model.chats = [chat("chat", {id: "newer"})]; wait(0);
      respond("messages", {items: [message("old", 1, {text: "Old"})]});
      respond("messages", {items: [message("new", 2, {type: "VOICE"})]});
      compare(preview(), "Voice message");
    }
    function test_invalidation_refreshes_reactions_even_when_preview_id_is_unchanged() {
      model.chats = [chat()]; tryVerify(() => model.requests.length === 1);
      resolver.invalidate("chat"); wait(0);
      respond("messages", {items: [message("old", 1, {text: "Stale"})]});
      respond("messages", {items: [message("new", 2, {text: "Updated"})]});
      compare(preview(), "Updated");
    }
    function test_scan_pages_without_looping_on_repeated_cursor() {
      model.chats = [chat()];
      respond("messages", {items: [], hasMore: true, oldestCursor: "older"});
      compare(model.requests[0].params.cursor, "older");
      respond("messages", {items: [], hasMore: true, oldestCursor: "older"});
      verify(!resolver.busy); compare(model.requests.length, 0);
    }
    function test_reconnect_discards_old_responses_and_resumes_queue() {
      model.chats = [chat()]; tryVerify(() => model.requests.length === 1);
      model.connected = false; model.connected = true; wait(0);
      respond("messages", {items: [message("stale", 1, {text: "Old"})]});
      respond("messages", {items: [message("current", 2, {text: "New"})]});
      compare(preview(), "New"); verify(!resolver.busy);
    }
    function test_errors_do_not_loop_or_block_other_previews() {
      model.chats = [chat("a"), chat("b")];
      respond("messages", null, {message: "Unavailable"});
      respond("messages", {items: [message("voice", 1, {type: "VOICE"})]});
      model.chats = model.chats.slice(); wait(0);
      compare(model.requests.length, 0);
      compare(fixture.format.preview(model.chats[1], resolver.entries), "Voice message");
    }
  }
}
