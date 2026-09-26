import QtQuick
import QtTest
import Quickshell

// Signals only: no recorder, filesystem access, API or microphone is created.
ShellRoot {
  id: fixture
  property var composer: null
  QtObject {
    id: model
    property string currentChatID: "chat"
    property var currentChat: ({id: "chat", isReadOnly: false})
    property string draftText: ""
    property string replyToMessageID: ""
    property var draftAttachment: null
    property bool sending: false
    property bool connected: true
    property bool demo: true
    function quote(id) { return {state: "missing", message: null}; }
  }
  Window { id: window; width: 800; height: 500; visible: true }
  SignalSpy { id: sendSpy; target: fixture.composer; signalName: "submitRequested" }
  SignalSpy { id: recordSpy; target: fixture.composer; signalName: "recordingToggleRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperComposer"
    when: window.visible
    function init() {
      model.currentChatID = "chat"; model.currentChat = {id: "chat", isReadOnly: false};
      model.draftText = ""; model.draftAttachment = null; model.replyToMessageID = "";
      model.connected = true; model.sending = false;
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperComposer.qml");
      compare(component.status, Component.Ready, component.errorString());
      fixture.composer = component.createObject(window.contentItem, {width: 700, beeperData: model, active: true});
      fixture.composer.draftTextEdited.connect(text => model.draftText = text);
      fixture.composer.editTextEdited.connect(text => fixture.composer.editText = text);
      verify(fixture.composer !== null); wait(20); sendSpy.clear(); recordSpy.clear();
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      fixture.composer.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperComposer: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function child(name) { return findChild(fixture.composer, name); }
    function test_one_line_resting_height_and_microphone_default() {
      compare(fixture.composer.implicitHeight, 48);
      verify(!fixture.composer.sendMode);
      compare(child("beeperComposerMicrophone").opacity, 1);
      compare(child("beeperComposerSendIcon").opacity, 0);
      mouseClick(child("beeperComposerAction"));
      compare(recordSpy.count, 1); compare(sendSpy.count, 0);
    }
    function test_typing_morphs_to_send_and_clearing_restores_microphone() {
      model.draftText = "Hello"; tryCompare(fixture.composer, "sendReveal", 1);
      verify(fixture.composer.sendMode);
      mouseClick(child("beeperComposerAction"));
      compare(sendSpy.count, 1); compare(recordSpy.count, 0);
      model.draftText = ""; tryCompare(fixture.composer, "sendReveal", 0);
      mouseClick(child("beeperComposerAction")); compare(recordSpy.count, 1);
    }
    function test_multiline_grows_only_as_needed_and_is_bounded() {
      model.draftText = "One\nTwo\nThree"; wait(20);
      verify(fixture.composer.implicitHeight > 48);
      model.draftText = "A line\n".repeat(40); wait(20);
      compare(fixture.composer.implicitHeight, 168);
      model.draftText = ""; wait(20); compare(fixture.composer.implicitHeight, 48);
    }
    function test_recording_can_always_be_stopped_even_when_disconnected() {
      fixture.composer.recording = true; model.connected = false;
      verify(fixture.composer.input.readOnly);
      verify(child("beeperComposerAction").enabled);
      mouseClick(child("beeperComposerAction")); compare(recordSpy.count, 1); compare(sendSpy.count, 0);
      fixture.composer.recording = false; verify(!child("beeperComposerAction").enabled);
    }
    function test_edit_and_attachment_modes_use_send_not_record() {
      fixture.composer.editMessageID = "edit"; fixture.composer.editText = "Edited text";
      verify(fixture.composer.sendMode); mouseClick(child("beeperComposerAction")); compare(sendSpy.count, 1);
      fixture.composer.editMessageID = "";
      model.draftAttachment = {type: "file", fileName: "Fictional.txt"};
      verify(fixture.composer.sendMode); mouseClick(child("beeperComposerAction")); compare(sendSpy.count, 2);
      model.sending = true; verify(!child("beeperComposerAction").enabled);
    }
    function openPicker(query) {
      mouseClick(child("beeperComposerEmoji"));
      tryCompare(fixture.composer, "emojiPickerOpen", true);
      const picker = child("beeperEmojiPicker");
      tryVerify(() => picker.searchInput.activeFocus);
      picker.searchInput.text = query;
      return picker;
    }
    function test_emoji_search_inserts_at_saved_cursor_without_sending() {
      model.draftText = "Salut Léa";
      fixture.composer.input.forceActiveFocus(); fixture.composer.input.cursorPosition = 6;
      const picker = openPicker("coeur");
      tryVerify(() => picker.matches.some(entry => entry.emoji === "❤️"));
      picker.grid.currentIndex = picker.matches.findIndex(entry => entry.emoji === "❤️");
      keyClick(Qt.Key_Return);
      tryCompare(fixture.composer, "emojiPickerOpen", false);
      compare(model.draftText, "Salut ❤️Léa");
      compare(fixture.composer.input.cursorPosition, 6 + "❤️".length);
      verify(fixture.composer.input.activeFocus);
      compare(sendSpy.count, 0); compare(recordSpy.count, 0);
    }
    function test_emoji_replaces_selection_with_complete_unicode_sequence() {
      fixture.composer.editMessageID = "edit"; fixture.composer.editText = "Hello friend!";
      fixture.composer.input.forceActiveFocus(); fixture.composer.input.select(6, 12);
      const emoji = "👩🏽‍💻", picker = openPicker(emoji);
      tryVerify(() => picker.matches.some(entry => entry.emoji === emoji));
      const index = picker.matches.findIndex(entry => entry.emoji === emoji);
      picker.grid.currentIndex = index;
      picker.grid.positionViewAtIndex(index, GridView.Contain); picker.grid.forceLayout(); wait(20);
      const button = picker.grid.currentItem;
      verify(button !== null); mouseClick(button);
      compare(fixture.composer.editText, "Hello " + emoji + "!");
      compare(fixture.composer.input.cursorPosition, 6 + emoji.length);
      compare(model.draftText, ""); compare(sendSpy.count, 0);
    }
    function test_emoji_escape_preserves_text_and_selection() {
      model.draftText = "Keep this selection";
      fixture.composer.input.forceActiveFocus(); fixture.composer.input.select(5, 9);
      openPicker("heart"); keyClick(Qt.Key_Escape);
      tryCompare(fixture.composer, "emojiPickerOpen", false);
      verify(fixture.composer.input.activeFocus);
      compare(fixture.composer.input.selectedText, "this");
      compare(model.draftText, "Keep this selection"); compare(sendSpy.count, 0);
    }
    function test_emoji_picker_closes_when_chat_changes_or_editing_is_disabled() {
      fixture.composer.input.forceActiveFocus(); const picker = openPicker("smile");
      model.currentChatID = "another"; model.draftText = "Other conversation";
      tryCompare(fixture.composer, "emojiPickerOpen", false);
      fixture.composer.insertEmoji("😀"); compare(model.draftText, "Other conversation");
      openPicker("smile"); fixture.composer.recording = true;
      tryCompare(fixture.composer, "emojiPickerOpen", false);
      verify(!child("beeperComposerEmoji").enabled);
      fixture.composer.recording = false; model.currentChat = {id: "another", isReadOnly: true};
      verify(!child("beeperComposerEmoji").enabled);
      compare(sendSpy.count, 0); compare(recordSpy.count, 0);
    }
    function test_emoji_no_match_and_navigation_do_not_send() {
      fixture.composer.input.forceActiveFocus();
      const picker = openPicker("no-such-emoji-zzzzzz");
      compare(picker.matches.length, 0); keyClick(Qt.Key_Return);
      verify(fixture.composer.emojiPickerOpen); compare(sendSpy.count, 0);
      picker.searchInput.text = "grinning"; tryVerify(() => picker.matches.length > 1);
      keyClick(Qt.Key_Down); verify(picker.grid.activeFocus);
      keyClick(Qt.Key_Right); compare(picker.grid.currentIndex, 1);
      const expected = picker.matches[1].emoji;
      keyClick(Qt.Key_Return);
      compare(model.draftText, expected); compare(sendSpy.count, 0);
    }
  }
}
