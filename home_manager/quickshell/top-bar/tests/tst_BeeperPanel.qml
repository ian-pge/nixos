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
    const dc = Qt.createComponent("file://" + Quickshell.shellDir + "/../BeeperData.qml");
    const pc = Qt.createComponent("file://" + Quickshell.shellDir + "/../components/BeeperPanel.qml");
    if (dc.status !== Component.Ready || pc.status !== Component.Ready) { console.error(dc.errorString(), pc.errorString()); Qt.exit(1); return; }
    beeperData = dc.createObject(fixture, {demo: true});
    format = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../components/BeeperFormat.js" as F; QtObject { property var library: F }', fixture).library;
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
      beeperData.selectChat("studio"); beeperData.draftText = ""; beeperData.draftAttachment = null; beeperData.replyToMessageID = "";
      panel.width = 1280; panel.messageIndex = -1; panel.chatIndex = 0;
      child("beeperSearch").text = "";
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
    function test_shift_enter_inserts_line_without_send() {
      panel.compose(); const before = beeperData.messages.length;
      child("beeperComposer").text = "Première ligne";
      keyClick(Qt.Key_Return, Qt.ShiftModifier);
      verify(child("beeperComposer").text.includes("\n"));
      compare(beeperData.messages.length, before);
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
      keyClick(Qt.Key_I); verify(child("beeperComposer").activeFocus);
      keyClick(Qt.Key_Escape); verify(!child("beeperComposer").activeFocus); compare(closeSpy.count, 0);
      panel.openModal("help"); wait(0);
      keyClick(Qt.Key_Escape); compare(panel.modal, ""); compare(closeSpy.count, 0);
      keyClick(Qt.Key_Escape); compare(closeSpy.count, 1);
    }
    function test_action_palette_keyboard() {
      panel.openModal("actions"); wait(0);
      child("beeperActionQuery").text = "aide";
      compare(panel.filteredActions.length, 1);
      keyClick(Qt.Key_Return); compare(panel.modal, "help");
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
    function test_delete_captures_message_before_selection_moves() {
      panel.messageIndex = beeperData.messages.findIndex(message => message.id === "2");
      verify(panel.messageIndex >= 0);
      panel.openModal("delete"); panel.submitModal();
      const otherID = beeperData.messages[0].id;
      panel.messageIndex = 0;
      wait(20);
      verify(!beeperData.messages.some(message => message.id === "2"));
      verify(beeperData.messages.some(message => message.id === otherID));
    }
    function test_transfer_restores_scroll_without_marking_latest() {
      const rows = [];
      for (let i = 0; i < 45; ++i) rows.push({id: "scroll-" + i, chatID: "studio", text: "Message dans l’historique " + i, senderName: "Contact", timestamp: new Date(Date.now() + i * 1000).toISOString()});
      beeperData.demoMessages.studio = beeperData.demoMessages.studio.concat(rows);
      beeperData.loadMessages(false); wait(30);
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
    function test_read_requires_focused_latest_messages() {
      delete beeperData.readMarkers.studio;
      panel.windowFocused = false; panel.updateView();
      wait(200); verify(beeperData.readMarkers.studio === undefined);
      panel.windowFocused = true;
      child("beeperMessages").positionViewAtEnd(); panel.updateView();
      wait(200); compare(beeperData.readMarkers.studio, beeperData.messages[beeperData.messages.length - 1].id);
    }
    function test_message_text_is_plain_and_media_has_width() {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../components/BeeperMessage.qml");
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(window.contentItem, {width: 600, message: {id: "x", text: "<b>Du texte</b>", attachments: [{type: "image"}]}});
      verify(item !== null); wait(0);
      const body = findChild(item, "messageBody");
      compare(body.textFormat, Text.PlainText);
      verify(body.width > 350); verify(item.implicitHeight > 200); item.destroy();
    }
  }
}
