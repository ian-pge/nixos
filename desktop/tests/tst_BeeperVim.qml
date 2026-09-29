import QtQuick
import QtTest
import Quickshell

// Vim editing in the real messenger panel, with an in-memory transport:
// nothing is sent, and the clipboard is replaced by a list.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  property var copiedTexts: []
  Window { id: window; width: 1280; height: 900; visible: true }
  SignalSpy { id: pasteSpy; signalName: "pasteAttachmentRequested" }
  TestResult { id: results }
  TestCase {
    name: "BeeperVim"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props);
      verify(item !== null); return item;
    }
    function composer() { return panel.composer; }
    function vim() { return findChild(panel, "beeperComposerVim"); }
    function block() { return findChild(vim(), "vimBlockCursor"); }
    function pending(method) { return beeperData.requests.filter(request => request.method === method); }
    function type(text) { for (const character of text) keyClick(character); }
    function press(keys) { for (const key of keys) keyClick(key); }
    function init() {
      fixture.copiedTexts = [];
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true, vimEditing: true,
          clipboardWriter: text => { fixture.copiedTexts = fixture.copiedTexts.concat([text]); }});
      beeperData.chats = [{id: "chat-a", title: "First chat", capabilities: {reaction: 2}}];
      beeperData.selectChat("chat-a");
      beeperData.respond("messages", {items: [{id: "message-0", chatID: "chat-a", senderName: "Contact", text: "Hello",
        timestamp: new Date(1700000000000).toISOString()}], hasMore: false});
      tryCompare(panel, "restoringView", false);
      pasteSpy.target = findChild(panel, "beeperComposerSurface"); pasteSpy.clear();
      panel.compose(); tryVerify(() => composer().activeFocus); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperVim: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }

    function test_writing_starts_in_insert_mode_with_a_monospace_font() {
      compare(vim().mode, "insert"); verify(!composer().readOnly); verify(!block().visible);
      compare(composer().font.family, "JetBrainsMono Nerd Font");
      type("hi"); compare(composer().text, "hi"); compare(beeperData.draftText, "hi");
    }
    function test_escape_enters_normal_mode_then_leaves_the_composer() {
      type("hello");
      keyClick(Qt.Key_Escape);
      compare(vim().mode, "normal"); verify(composer().activeFocus); compare(panel.navigation, "compose");
      verify(composer().readOnly); verify(block().visible); compare(composer().cursorPosition, 4);
      keyClick(Qt.Key_Escape);
      verify(!composer().activeFocus); compare(panel.navigation, "chats");
      compare(beeperData.draftText, "hello");
    }
    function test_escape_in_normal_mode_still_cancels_a_reply_first() {
      beeperData.replyToMessageID = "message-0";
      type("ok"); keyClick(Qt.Key_Escape); keyClick(Qt.Key_Escape);
      compare(beeperData.replyToMessageID, ""); verify(composer().activeFocus); compare(vim().mode, "normal");
    }
    function test_normal_mode_commands_edit_the_draft_with_one_step_undo() {
      type("one two three"); keyClick(Qt.Key_Escape);
      press(["0", "d", "w"]);
      compare(composer().text, "two three"); compare(beeperData.draftText, "two three");
      press(["c", "w"]); compare(vim().mode, "insert"); type("deux"); keyClick(Qt.Key_Escape);
      compare(beeperData.draftText, "deux three");
      keyClick("u"); compare(composer().text, "two three");
      keyClick("u"); compare(composer().text, "one two three");
      keyClick(Qt.Key_R, Qt.ControlModifier); compare(composer().text, "two three");
    }
    function test_normal_mode_never_types_text() {
      type("abc"); keyClick(Qt.Key_Escape);
      keyClick("z"); keyClick("?");
      // Qt's test keyboard only knows ASCII: send the dead-key result directly.
      compare(vim().handleKeyEvent({key: 0, text: "é", modifiers: 0, isAutoRepeat: false, accepted: false}), true); keyClick(Qt.Key_Space); keyClick(Qt.Key_Tab);
      compare(composer().text, "abc"); compare(panel.modal, "");
      keyClick(Qt.Key_V, Qt.ControlModifier);
      compare(composer().text, "abc"); compare(pasteSpy.count, 0);
    }
    function test_vertical_motion_follows_wrapped_lines() {
      type("wrapped ".repeat(40)); keyClick(Qt.Key_Escape);
      verify(composer().lineCount > 1); verify(composer().text.indexOf("\n") < 0);
      press(["g", "g"]);
      const top = composer().positionToRectangle(composer().cursorPosition);
      keyClick("j");
      const below = composer().positionToRectangle(composer().cursorPosition);
      verify(composer().cursorPosition > 0); verify(below.y > top.y); compare(below.x, top.x);
      keyClick("k"); compare(composer().cursorPosition, 0);
    }
    function test_block_cursor_is_one_monospace_cell() {
      type("abc"); keyClick(Qt.Key_Escape); keyClick("0");
      const cell = composer().positionToRectangle(1).x - composer().positionToRectangle(0).x;
      verify(cell > 0); fuzzyCompare(block().width, cell, 0.5);
      compare(block().x, composer().positionToRectangle(0).x);
    }
    function test_cursor_colors_match_zed() {
      verify(Qt.colorEqual(findChild(panel, "beeperComposerCursor").color, "#ffcc33"));
      type("abc"); keyClick(Qt.Key_Escape); keyClick("0");
      verify(Qt.colorEqual(block().color, "#ffcc33")); compare(block().color.a, 1);
      const glyph = findChild(block(), "vimBlockText");
      compare(glyph.text, "a"); verify(Qt.colorEqual(glyph.color, "#24273a"));
      compare(glyph.font.family, composer().font.family); compare(glyph.font.pixelSize, composer().font.pixelSize);
      keyClick("$"); compare(glyph.text, "c");
    }
    function test_block_cursor_blinks_and_shows_solid_after_moving() {
      type("abc"); keyClick(Qt.Key_Escape);
      compare(block().opacity, 1);
      tryCompare(block(), "opacity", 0, 3000);
      keyClick("h"); compare(block().opacity, 1);
      tryCompare(block(), "opacity", 0, 3000);
      tryCompare(block(), "opacity", 1, 3000);
    }
    function matchBoxes(name) { return vim().children.filter(child => child.objectName === name); }
    function test_slash_search_highlights_while_typing_then_jumps() {
      type("salut toi, SALUT moi"); keyClick(Qt.Key_Escape); keyClick("0");
      const surface = findChild(panel, "beeperComposerSurface");
      const prompt = findChild(panel, "vimSearchPrompt");
      compare(surface.implicitHeight, 48); verify(!prompt.visible);
      keyClick("/");
      verify(vim().searching); tryVerify(() => prompt.visible); compare(prompt.text, "/");
      tryVerify(() => surface.implicitHeight > 48); verify(!block().visible);
      type("sal");
      compare(prompt.text, "/sal"); compare(composer().text, "salut toi, SALUT moi");
      compare(matchBoxes("vimMatch").length, 1); compare(matchBoxes("vimCurrentMatch").length, 1);
      const current = matchBoxes("vimCurrentMatch")[0];
      compare(current.x, composer().positionToRectangle(11).x);
      fuzzyCompare(current.width, composer().positionToRectangle(14).x - composer().positionToRectangle(11).x, 0.5);
      verify(Qt.colorEqual(current.color, "#4ded8796")); verify(Qt.colorEqual(matchBoxes("vimMatch")[0].color, "#4d8bd5ca"));
      keyClick(Qt.Key_Return);
      compare(composer().cursorPosition, 11); verify(!vim().searching); verify(!prompt.visible);
      compare(matchBoxes("vimMatch").length + matchBoxes("vimCurrentMatch").length, 0);
      verify(block().visible); compare(vim().mode, "normal"); tryCompare(surface, "implicitHeight", 48);
      compare(beeperData.draftText, "salut toi, SALUT moi");
      keyClick("n"); compare(composer().cursorPosition, 0);
      keyClick("N"); compare(composer().cursorPosition, 11);
    }
    function test_slash_search_escape_cancels_and_misses_turn_red() {
      type("abc abc"); keyClick(Qt.Key_Escape); keyClick("0");
      const prompt = findChild(panel, "vimSearchPrompt");
      keyClick("/"); type("zz");
      verify(Qt.colorEqual(prompt.color, "#ed8796")); compare(matchBoxes("vimCurrentMatch").length, 0);
      keyClick(Qt.Key_Backspace); keyClick(Qt.Key_Backspace); type("abc");
      verify(!Qt.colorEqual(prompt.color, "#ed8796"));
      keyClick(Qt.Key_Escape);
      verify(!vim().searching); compare(composer().cursorPosition, 0);
      verify(composer().activeFocus); compare(panel.navigation, "compose"); compare(vim().mode, "normal");
    }
    function test_visual_selection_and_yank_reach_the_clipboard() {
      type("hello world"); keyClick(Qt.Key_Escape); keyClick("0");
      press(["v", "e"]); compare(vim().mode, "visual"); compare(composer().selectedText, "hello");
      keyClick("y"); compare(vim().mode, "normal"); compare(composer().selectedText, "");
      compare(fixture.copiedTexts, ["hello"]); compare(panel.notice, "Text copied");
      press(["w", "y", "i", "w"]); compare(fixture.copiedTexts, ["hello", "world"]);
      press(["d", "w"]); compare(fixture.copiedTexts, ["hello", "world"]);
    }
    function test_enter_sends_from_normal_mode_and_returns_to_insert() {
      type("hi"); keyClick(Qt.Key_Escape);
      keyClick(Qt.Key_Return, Qt.ShiftModifier); compare(pending("send").length, 0);
      keyClick(Qt.Key_Return);
      compare(pending("send").length, 1); compare(pending("send")[0].params.text, "hi");
      compare(vim().mode, "insert"); verify(composer().activeFocus); verify(!composer().readOnly);
    }
    function test_returning_to_the_composer_restarts_insert_mode() {
      type("abc"); keyClick(Qt.Key_Escape); compare(vim().mode, "normal");
      keyClick(Qt.Key_K, Qt.ControlModifier); verify(!composer().activeFocus);
      keyClick("l"); verify(composer().activeFocus); compare(vim().mode, "insert");
      type("d"); compare(composer().text, "abcd");
    }
    function test_help_documents_vim_only_when_enabled() {
      keyClick(Qt.Key_Escape); keyClick(Qt.Key_Escape); keyClick("?");
      const help = findChild(panel, "beeperKeyboardHelp");
      verify(help.text.indexOf("COMPOSER · VIM MODE") >= 0);
      keyClick(Qt.Key_Escape); panel.vimEditing = false; keyClick("?");
      verify(help.text.indexOf("VIM MODE") < 0); verify(help.text.indexOf("EMOJI PICKER") >= 0);
    }
    function test_without_vim_escape_leaves_directly_and_letters_type() {
      panel.vimEditing = false; panel.compose();
      type("x"); compare(composer().text, "x");
      keyClick(Qt.Key_Escape); compare(panel.navigation, "chats"); verify(!composer().activeFocus);
    }
    function test_recording_suspends_vim() {
      type("a"); keyClick(Qt.Key_Escape);
      panel.preparingRecording = true; verify(!vim().active); compare(vim().mode, "insert"); verify(composer().readOnly);
      panel.preparingRecording = false; verify(vim().active); compare(vim().mode, "insert"); verify(!composer().readOnly);
    }
  }
}
