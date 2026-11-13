import QtQuick
import QtTest
import Quickshell

// The Qwen panel and the morphing bottom notch, with an in-memory transport.
// Neither Ollama nor the Go helper is started.
ShellRoot {
  id: fixture
  Window { id: window; width: 1400; height: 1000; visible: true }
  property var store: null
  property var panel: null
  property var notch: null
  property var copied: []
  property var opened: []
  QtObject {
    id: weather
    property var days: ({})
    property string temperatureText: "11°"
  }
  QtObject {
    id: calendar
    property date today: new Date(2026, 10, 12, 12)
    property string timeText: "12:00"
    property var weather: weather
  }
  QtObject {
    id: assistant
    property var assistantData: fixture.store
    property bool visible: false
    property bool passive: false
    property bool blocked: false
    property string targetMonitor: "eDP-1"
    property int focusSerial: 0
    function show(monitor) { targetMonitor = monitor || "eDP-1"; visible = true; ++focusSerial; }
    function hide() { visible = false; }
  }
  TestResult { id: results }
  TestCase {
    name: "Assistant"
    when: window.visible
    function create(file, parent, props) {
      const c = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(c.status, Component.Ready, c.errorString());
      const item = c.createObject(parent, props); verify(item !== null); return item;
    }
    function init() {
      copied = []; opened = [];
      store = create("fixtures/FakeAssistantData.qml", fixture, {});
      panel = create("../features/assistant/AssistantPanel.qml", window.contentItem,
        {assistantData: store, width: 960, height: 700, active: true, windowFocused: true,
         clipboardWriter: text => { copied = copied.concat([text]); }, linkOpener: url => { opened = opened.concat([url]); return true; }});
      window.requestActivate();
      tryVerify(() => panel.composer.activeFocus);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      if (notch) { notch.destroy(); notch = null; }
      panel.active = false; panel.destroy(); store.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("Assistant: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function snapshot(revision, items, extra) {
      return Object.assign({revision: revision, resetRevision: 0, generating: false, unloading: false, items: items}, extra || {});
    }
    function stream(revision, items, extra) { store.acceptLine(JSON.stringify({event: "changed", data: snapshot(revision, items, extra)})); }
    function find(name) { return findChild(panel, name); }

    function test_send_streams_and_stop_keeps_next_draft() {
      store.draftText = "Bonjour Qwen";
      keyClick(Qt.Key_Return);
      compare(store.pending("send").length, 1); compare(store.pending("send")[0].params.text, "Bonjour Qwen");
      compare(store.draftText, "", "The composer clears at once");
      stream(1, [store.message("u", "user", "Bonjour Qwen"), store.message("a", "assistant", "…", {state: "generating"})], {generating: true});
      store.respond("send", {messageID: "u"});
      compare(store.messages.length, 2); verify(store.generating);
      compare(find("assistantAction").Accessible.name, "Stop the reply");
      store.draftText = "suite";
      find("assistantAction").clicked();
      compare(store.pending("cancel").length, 1, "The send button stops a running reply");
      stream(3, [store.message("a", "assistant", "Bonjour !", {state: "stopped"})]);
      compare(store.messages[1].text, "Bonjour !"); verify(!store.generating);
      compare(store.draftText, "suite");
      // An older chunk arriving late never replaces a newer snapshot.
      stream(2, [store.message("a", "assistant", "Bon", {state: "generating"})], {generating: true});
      compare(store.messages[1].text, "Bonjour !"); verify(!store.generating);
    }
    function test_failed_send_restores_the_draft() {
      store.draftText = "Question";
      panel.submit();
      store.respond("send", null, {message: "Wait for Qwen's current action to finish."});
      compare(store.draftText, "Question");
      compare(store.lastError, "Wait for Qwen's current action to finish.");
      verify(find("assistantError").visible);
    }
    function test_reset_and_unload_shortcuts_keep_draft() {
      stream(1, [store.message("u", "user", "Avant")]);
      store.draftText = "Brouillon";
      keyClick(Qt.Key_S, Qt.ControlModifier);
      compare(store.pending("reset").length, 1); verify(store.busy);
      verify(!find("assistantAction").enabled, "No send or unload while resetting");
      store.respond("reset", snapshot(2, [], {resetRevision: 2}));
      compare(store.messages.length, 0); compare(store.draftText, "Brouillon");
      compare(panel.notice, "Conversation reset");
      keyClick(Qt.Key_S, Qt.ControlModifier);
      compare(store.pending("reset").length, 0, "An empty conversation has nothing to reset");
      keyClick(Qt.Key_D, Qt.ControlModifier);
      compare(store.pending("unload").length, 1);
      store.respond("unload", {unloaded: true});
      compare(panel.notice, "Model unloaded · Next message will reload it");
      compare(store.draftText, "Brouillon");
    }
    function test_empty_draft_turns_action_into_unload() {
      compare(find("assistantAction").Accessible.name, "Unload Qwen from GPU");
      find("assistantAction").clicked();
      compare(store.pending("unload").length, 1);
      store.respond("unload", null, {message: "Ollama unavailable"});
      verify(!store.busy);
    }
    function test_message_keys_copy_source_and_open_links() {
      stream(1, [store.message("u", "user", "Lien ?"),
        store.message("a", "assistant", "Voir **ceci**", {html: '<p>Voir <a href="https://example.test/?a=1&amp;b=2">ceci</a></p>'})]);
      keyClick(Qt.Key_H, Qt.ControlModifier);
      verify(!panel.composer.activeFocus);
      keyClick(Qt.Key_K); compare(panel.messageIndex, 1);
      keyClick(Qt.Key_Y); compare(copied[0], "Voir **ceci**");
      keyClick(Qt.Key_L); compare(opened[0], "https://example.test/?a=1&b=2");
      keyClick(Qt.Key_K); compare(panel.messageIndex, 0);
      keyClick(Qt.Key_Return); verify(panel.composer.activeFocus); compare(panel.messageIndex, -1);
    }
    function test_search_loads_older_pages_until_the_match() {
      store.applySnapshot(snapshot(1, [store.message("new", "user", "récent")], {hasMore: true, oldestCursor: "1"}));
      keyClick(Qt.Key_Slash, Qt.ControlModifier);
      tryVerify(() => find("assistantSearchField").activeFocus);
      find("assistantSearchField").text = "ancien";
      keyClick(Qt.Key_Return);
      compare(store.pending("search").length, 1);
      store.respond("search", {ids: ["old"]});
      compare(store.pending("messages").length, 1); compare(store.pending("messages")[0].params.cursor, "1");
      store.respond("messages", {items: [store.message("old", "user", "ancien message", {timestamp: "2026-11-11T10:00:00Z"})], hasMore: false, oldestCursor: "0", revision: 1, resetRevision: 0});
      compare(store.messages[0].id, "old");
      tryCompare(panel, "messageIndex", 0);
      compare(find("assistantSearchCount").text, "1 / 1");
      keyClick(Qt.Key_Escape); verify(!panel.searchOpen);
    }
    function test_spelling_correction_applies_only_to_unchanged_draft() {
      store.draftText = "Les fille"; panel.composer.cursorPosition = panel.composer.length;
      keyClick(Qt.Key_Tab, Qt.ControlModifier | Qt.AltModifier);
      compare(store.pending("correctText").length, 1); compare(store.pending("correctText")[0].params.text, "Les fille");
      const id=store.pending("correctText")[0].params.reportId;
      store.respond("correctText", {reportId:id,text: "Les filles", edits: [{start: 4, end: 9, replacement: "filles"}]});
      compare(store.draftText,"Les fille");
      store.acceptLine(JSON.stringify({event:"correctionChanged",data:{id:id,provider:"qwen",state:"accepted"}}));
      store.dismissCorrection();panel.compose();
      compare(store.draftText, "Les filles"); compare(store.pending("send").length, 0);
      keyClick(Qt.Key_Tab, Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier);
      compare(store.draftText, "Les fille");
    }
    function test_correction_report_highlights_and_explains_without_notice() {
      store.acceptLine(JSON.stringify({event:"correctionChanged",data:{id:"c1",provider:"openai",state:"applied",
        html:'<p>Les <span style="color:#ed8796;font-weight:600">filles</span> sont <span style="color:#ed8796;font-weight:600">allées</span> au cinéma.</p>',
        explanations:[{from:"fille",to:"filles",reason:"Avec « les », le nom est au pluriel."},{from:"aller",to:"allées",reason:"Avec être, le participe passé s’accorde avec le sujet féminin pluriel."}]}}));
      verify(panel.showingCorrection);compare(panel.notice,"");
      verify(find("assistantCorrectionLogo").source.toString().endsWith("assets/openai/logo.svg"));
      verify(!find("assistantCorrectionStatus").visible);
      const text=findChild(panel,"assistantCorrectedText");verify(text.visible);verify(text.text.includes("#ed8796"));
      wait(100);const screenshot=Quickshell.env("QS_CORRECTION_SCREENSHOT");if(screenshot)grabImage(panel).save(screenshot);
    }
    function test_correction_opens_immediately_and_stays_dismissed() {
      const controller = create("../shell/AssistantController.qml", fixture,
        {assistantData: store, focusedMonitor: "eDP-1", availableMonitors: ["eDP-1"]});
      let presentations = 0;
      store.correctionPresented.connect(() => ++presentations);
      try {
        const report = {id:"pending-correction",provider:"qwen",state:"running",source:"Les fille <exemple>"};
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:report}));
        verify(controller.visible); verify(controller.passive); compare(controller.focusSerial,0);
        verify(panel.showingCorrection);
        compare(find("assistantCorrectionReport").color.toString(),"#000000");
        verify(find("assistantCorrectionProgress").running);
        verify(find("assistantCorrectionLogo").source.toString().endsWith("assets/qwen/logo.png"));
        verify(!find("assistantCorrectionStatus").visible);
        const editor=find("assistantCorrectedText");
        compare(editor.getText(0,editor.length),"Les fille <exemple>");
        wait(100);
        const screenshot=Quickshell.env("QS_CORRECTION_LOADING_SCREENSHOT");
        if(screenshot)grabImage(panel).save(screenshot);
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:Object.assign({},report,{state:"ready",html:"<p>Les filles &lt;exemple&gt;</p>"})}));
        compare(presentations,1);verify(!find("assistantCorrectionProgress").running);
        verify(!find("assistantCorrectionStatus").visible);
        compare(editor.getText(0,editor.length),"Les filles <exemple>");
        controller.hide();verify(!controller.visible);compare(store.correction,null);
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:Object.assign({},report,{state:"applied",html:"<p>Les filles</p>"})}));
        verify(!controller.visible);compare(store.correction,null);compare(presentations,1);
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:Object.assign({},report,{id:"next-correction"})}));
        verify(controller.visible);compare(presentations,2);
        controller.show();verify(!controller.passive);compare(store.correction,null);
      } finally {controller.destroy();wait(0);}
    }
    function test_correction_previews_its_own_draft_until_enter() {
      const controller=create("../shell/AssistantController.qml",fixture,{assistantData:store,focusedMonitor:"eDP-1",availableMonitors:["eDP-1"]});
      try {
        store.draftText="Les fille";panel.composer.cursorPosition=panel.composer.length;
        panel.correctSpelling();verify(panel.correctingSpelling);
        const id=store.pending("correctText")[0].params.reportId;
        const report={id:id,provider:"qwen",state:"running",source:"Les fille"};
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:report}));
        verify(panel.showingCorrection);verify(controller.visible);
        keyClick(Qt.Key_Return);compare(store.pending("decideCorrection").length,0);
        store.respond("correctText",{reportId:id,text:"Les filles",edits:[{start:4,end:9,replacement:"filles"}]});
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:Object.assign({},report,{state:"ready",html:"<p>Les filles</p>"})}));
        compare(store.draftText,"Les fille");verify(panel.correctingSpelling);
        keyClick(Qt.Key_Return);compare(store.pending("decideCorrection")[0].params.status,"accept");
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:Object.assign({},report,{state:"accepted"})}));
        compare(store.draftText,"Les filles");verify(!panel.correctingSpelling);verify(!controller.visible);
        compare(store.pending("finishCorrection")[0].params.status,"applied");compare(store.pending("send").length,0);
      } finally {controller.destroy();wait(0);}
    }
    function test_escape_keeps_original_even_if_the_result_arrives_late() {
      const controller=create("../shell/AssistantController.qml",fixture,{assistantData:store,focusedMonitor:"eDP-1",availableMonitors:["eDP-1"]});
      try {
        store.draftText="Les fille";panel.correctSpelling();
        const id=store.pending("correctText")[0].params.reportId;
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:{id:id,provider:"qwen",state:"running",source:"Les fille"}}));
        keyClick(Qt.Key_Escape);compare(store.pending("decideCorrection")[0].params.status,"reject");
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:{id:id,provider:"qwen",state:"dismissed"}}));
        verify(!controller.visible);verify(!panel.correctingSpelling);
        store.respond("correctText",{reportId:id,text:"Les filles",edits:[{}]});
        compare(store.draftText,"Les fille");compare(store.pending("send").length,0);
      } finally {controller.destroy();wait(0);}
    }
    function test_zoom_and_composer_expansion() {
      const size = store.textSize;
      keyClick(Qt.Key_Equal, Qt.ControlModifier); compare(store.textSize, size + 2);
      keyClick(Qt.Key_0, Qt.ControlModifier); compare(store.textSize, 18);
      const composer = find("assistantComposerSurface"), before = composer.height;
      const bottom = () => composer.mapToItem(panel, 0, composer.height).y;
      const restingBottom = bottom();
      keyClick(Qt.Key_Space, Qt.ControlModifier);
      tryVerify(() => composer.height > before + 300);
      tryVerify(() => Math.abs(bottom() - restingBottom) < 0.5, 1000, "The composer grows upward only");
      keyClick(Qt.Key_Space, Qt.ControlModifier);
      tryCompare(composer, "height", before);
    }
    function test_tab_switches_model_conversation_draft_and_logo() {
      stream(1, [store.message("q", "user", "Question Qwen")]);
      store.draftText = "brouillon Qwen";
      keyClick(Qt.Key_Tab);
      compare(store.pending("send").length, 0, "Tab inside the draft never switches");
      keyClick(Qt.Key_H, Qt.ControlModifier);
      keyClick(Qt.Key_Tab);
      compare(store.conversation, "openai"); compare(store.title, "OpenAI");
      compare(store.pending("saveDraft").pop().params.conversation, "qwen", "The Qwen draft is saved first");
      compare(store.pending("select")[0].params.conversation, "openai");
      compare(store.messages.length, 0); compare(store.draftText, "");
      const status = store.pending("status").pop();
      compare(status.params.conversation, "openai");
      store.respond("status", Object.assign(snapshot(5, [store.message("o", "user", "Question GPT")]), {conversation: "openai", draft: "brouillon GPT"}));
      compare(store.messages[0].id, "o"); compare(store.draftText, "brouillon GPT");
      compare(panel.accent, store.conversations[1].accent);
      const toggle = find("assistantModelSwitch");
      compare(toggle.model.key, "openai");
      // Qwen activity stays in its own conversation.
      stream(6, [store.message("q2", "assistant", "Réponse Qwen")], {conversation: "qwen", generating: true});
      compare(store.messages.length, 1); verify(!store.generating);
      // No GPU to unload for a remote model: the idle action is send.
      store.draftText = "";
      verify(!find("assistantAction").enabled);
      compare(find("assistantAction").Accessible.name, "Send message");
      keyClick(Qt.Key_D, Qt.ControlModifier);
      compare(store.pending("unload").length, 0);
      store.draftText = "Fais-le";
      panel.submit();
      compare(store.pending("send")[0].params.conversation, "openai");
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
      compare(store.conversation, "qwen");
      mouseClick(toggle);
      compare(store.conversation, "openai");
      verify(find("assistantModelCard").visible, "An empty conversation shows the model card");
    }
    function test_tab_in_vim_normal_mode_switches_and_keeps_the_caret() {
      panel.compose();
      const composer = find("assistantComposer"), vim = find("assistantComposerVim");
      keyClick(Qt.Key_Escape);
      compare(vim.mode, "normal");
      const before = store.conversation;
      keyClick(Qt.Key_Tab);
      verify(store.conversation !== before, "Tab in normal mode switches model");
      verify(composer.activeFocus, "The caret stays in the composer");
      keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
      compare(store.conversation, before);
    }
    function test_ctrl_tab_sets_thinking_from_green_to_red() {
      const dot = find("assistantThinkingDot"), surface = find("assistantComposerSurface");
      verify(dot.visible);
      const dotX = dot.mapToItem(panel, 0, 0).x, surfaceRight = surface.mapToItem(panel, surface.width, 0).x;
      verify(dotX > surfaceRight, "The dot sits right of a shorter composer");
      fuzzyCompare(dot.mapToItem(panel, 0, dot.height / 2).y, find("assistantAction").mapToItem(panel, 0, 20).y, 1, "Centered on the buttons");
      // Qwen: off (green) or on (red), also from inside the draft.
      store.draftText = "abc";
      compare(store.thinkingLevel, "off"); compare(String(dot.color), "#a6da95");
      keyClick(Qt.Key_Tab, Qt.ControlModifier);
      compare(store.draftText, "abc", "Ctrl+Tab never types a tab");
      compare(store.thinkingLevel, "high"); compare(store.thinkingName, "On");
      compare(store.pending("setThinking")[0].params.conversation, "qwen");
      compare(store.pending("setThinking")[0].params.level, "high");
      tryCompare(dot, "color", Qt.color("#ed8796"));
      compare(find("assistantNoticeText").text, "Thinking · On");
      // A streamed snapshot sent before the change cannot bring the old level back.
      stream(1, [], {thinkingLevel: "off"});
      compare(store.thinkingLevel, "high");
      store.respond("setThinking", snapshot(2, undefined, {thinkingLevel: "high"}));
      keyClick(Qt.Key_Tab, Qt.ControlModifier);
      compare(store.thinkingLevel, "off");
      // A refusal restores the previous level.
      store.respond("setThinking", null, {message: "Could not save the thinking level."});
      compare(store.thinkingLevel, "high");
      // OpenAI: low → medium → high → extra high, wrapping, and back with Shift.
      panel.switchModel(1);
      store.respond("status", snapshot(5, [], {conversation: "openai", thinkingLevel: "medium"}));
      compare(store.thinkingLevel, "medium");
      const colors = [];
      for (let i = 0; i < 4; ++i) { keyClick(Qt.Key_Tab, Qt.ControlModifier); colors.push(store.thinkingLevel + " " + store.thinkingColor); }
      compare(colors.join(", "), "high #f5a97f, xhigh #ed8796, low #a6da95, medium #eed49f");
      keyClick(Qt.Key_Backtab, Qt.ControlModifier | Qt.ShiftModifier);
      compare(store.thinkingLevel, "low");
      compare(store.pending("setThinking").pop().params.conversation, "openai");
      mouseClick(dot);
      compare(store.thinkingLevel, "medium", "A click steps to the next level");
    }
    function test_composer_buttons_stay_centered_at_every_text_size() {
      const surface = find("assistantComposerSurface"), reset = find("assistantReset"), action = find("assistantAction");
      const dot = find("assistantThinkingDot");
      for (const size of [14, 18, 22, 26, 30]) {
        store.setTextSize(size); wait(30);
        const r = reset.mapToItem(surface, 0, 0), a = action.mapToItem(surface, 0, 0);
        fuzzyCompare(surface.radius, surface.height / 2, 0.01, "A single line stays a capsule at " + size);
        fuzzyCompare(r.y, surface.height - r.y - reset.height, 1, "Reset centered vertically at " + size);
        fuzzyCompare(r.x, r.y, 1, "Reset concentric with the round end at " + size);
        fuzzyCompare(surface.width - a.x - action.width, a.y, 1, "Send concentric with the round end at " + size);
        fuzzyCompare(dot.mapToItem(surface, 0, dot.height / 2).y, surface.height / 2, 1, "The dot follows at " + size);
      }
      store.setTextSize(18);
    }
    function test_caret_stays_solid_while_typing() {
      panel.compose();
      const caret = find("assistantComposerCursor");
      verify(caret);
      caret.blinkOn = false;
      keyClick(Qt.Key_A);
      verify(caret.blinkOn, "Typing shows the caret");
    }
        function test_streaming_follows_until_the_user_scrolls_up() {
      const history = find("assistantHistory");
      let text = "Début";
      stream(1, [store.message("u", "user", "Q"), store.message("a", "assistant", text, {state: "generating"})], {generating: true});
      function grow(revision) {
        text += "<br/>ligne " + revision;
        stream(revision, [store.message("a", "assistant", text, {state: "generating"})], {generating: true});
        wait(20);
      }
      for (let i = 2; i < 50; ++i) grow(i);
      verify(history.contentHeight > history.height * 2);
      fuzzyCompare(history.contentY, history.contentHeight - history.height, 1, "Streaming stays at the end");
      mouseWheel(history, history.width / 2, history.height / 2, 0, 360);
      tryVerify(() => !panel.pinLatest && history.contentY < history.contentHeight - history.height - 100);
      wait(300); // let the wheel glide settle
      const reading = history.contentY;
      for (let i = 50; i < 55; ++i) grow(i);
      fuzzyCompare(history.contentY, reading, 1, "Reading position is kept while the reply grows");
      for (let n = 0; n < 40 && !panel.pinLatest; ++n) { mouseWheel(history, history.width / 2, history.height / 2, 0, -360); wait(30); }
      verify(panel.pinLatest, "Returning to the end resumes following");
      for (let i = 55; i < 60; ++i) grow(i);
      fuzzyCompare(history.contentY, history.contentHeight - history.height, 1);
    }
        function test_thinking_animates_until_text_then_resumes_for_tools() {
      // Only the reply: findChild returns the first bubble of the history.
      stream(1, [store.message("a", "assistant", "…", {state: "generating", thinking: true})], {generating: true});
      const label = find("assistantThinking");
      verify(label !== null && label.visible);
      verify(label.verbs.indexOf(label.verb) >= 0, "A playful verb replaces the model name");
      verify(!find("assistantMessageBody").visible || find("assistantMessageBody").html === "", "The placeholder is hidden");
      tryVerify(() => findChild(panel, "assistantAvatar").scale !== 1, 2000, "The avatar breathes");
      stream(2, [store.message("a", "assistant", "Bonjour", {state: "generating", thinking: false})], {generating: true});
      tryVerify(() => !find("assistantThinking").visible);
      stream(3, [store.message("a", "assistant", "Bonjour\n\n> ▸ **ls**", {state: "generating", thinking: true})], {generating: true});
      tryVerify(() => find("assistantThinking").visible, 1000, "A tool call thinks again under the text");
      stream(4, [store.message("a", "assistant", "Bonjour", {state: "complete", thinking: false})]);
      tryVerify(() => !find("assistantThinking").visible);
      compare(findChild(panel, "assistantAvatar").scale, 1);
    }
        function test_notch_grows_from_the_bottom_edge_and_folds_back() {
      panel.active = false;
      notch = create("../bar/BottomNotch.qml", window.contentItem,
        {calendar: calendar, assistant: assistant, panelWindow: null, monitorName: "eDP-1",
         availableWidth: 1400, availableHeight: 940, windowFocused: true});
      notch.anchors.bottom = window.contentItem.bottom;
      notch.anchors.horizontalCenter = window.contentItem.horizontalCenter;
      const compactWidth = notch.width, compactHeight = notch.height;
      compare(compactHeight, notch.compactHeight);
      verify(findChild(notch, "calendarNotch").visible);
      const pointer = findChild(notch, "calendarNotchPointer");
      mouseClick(pointer, pointer.width / 2, pointer.height / 2, Qt.RightButton);
      verify(assistant.visible); verify(notch.active);
      // Monotone growth on both axes, bottom edge fixed.
      let previous = notch.height;
      tryVerify(() => { verify(notch.height >= previous); previous = notch.height; return notch.height === notch.panelHeight; }, 1000);
      compare(notch.width, notch.panelWidth + 2 * notch.openCorner);
      compare(notch.mapToItem(window.contentItem, 0, notch.height).y, window.height);
      tryCompare(findChild(notch, "calendarNotch"), "visible", false);
      tryCompare(findChild(notch, "assistantPanel"), "opacity", 1);
      assistant.hide();
      tryCompare(notch, "height", compactHeight, 1000);
      compare(notch.width, compactWidth);
      tryCompare(notch, "presented", false);
      verify(findChild(notch, "calendarNotch").visible);
    }
    function test_correction_notch_fits_content_and_scrolls_long_reports() {
      panel.active = false;
      notch = create("../bar/BottomNotch.qml", window.contentItem,
        {calendar:calendar,assistant:assistant,panelWindow:null,monitorName:"eDP-1",availableWidth:1400,availableHeight:940});
      notch.anchors.bottom = window.contentItem.bottom;
      assistant.passive = true;
      const update = report => store.acceptLine(JSON.stringify({event:"correctionChanged",data:report}));
      const shortReport = {id:"sized-report",provider:"qwen",state:"applied",
        html:"<p>Les filles sont allées au cinéma.</p>",
        explanations:[{from:"fille",to:"filles",reason:"Avec « les », le nom est au pluriel."},
          {from:"aller",to:"allées",reason:"Avec être, le participe passé s’accorde avec le sujet féminin pluriel."}]};
      try {
        update({id:"sized-report",provider:"qwen",state:"running",source:"Les fille sont aller au cinéma."});
        assistant.visible = true;
        const report = findChild(notch,"assistantCorrectionReport");
        const scroll = findChild(notch,"assistantCorrectionScroll");
        tryVerify(() => notch.height === Math.ceil(report.implicitHeight));
        verify(notch.height < 250,"The loading panel fits a short source");
        const loadingHeight = notch.height;
        update(shortReport);
        tryVerify(() => notch.height > loadingHeight && notch.height === Math.ceil(report.implicitHeight));
        verify(notch.height < 400,"A short correction leaves the rest of the screen free");
        verify(scroll.contentHeight <= scroll.availableHeight + 1,"The full report fits without scrolling");
        compare(notch.mapToItem(window.contentItem,0,notch.height).y,window.height);
        const wideHeight = notch.height;
        notch.availableWidth = 480;
        tryVerify(() => notch.height > wideHeight && notch.height === Math.ceil(report.implicitHeight));
        notch.availableWidth = 1400;
        tryCompare(notch,"height",wideHeight);
        const screenshot=Quickshell.env("QS_CORRECTION_COMPACT_SCREENSHOT");
        if(screenshot)grabImage(notch).save(screenshot);
        update(Object.assign({},shortReport,{html:"<p>Une longue correction.</p>".repeat(90)}));
        tryCompare(notch,"height",notch.maximumPanelHeight);
        verify(scroll.contentHeight > scroll.availableHeight,"Long reports scroll inside the capped panel");
        compare(notch.mapToItem(window.contentItem,0,notch.height).y,window.height);
        update(shortReport);
        tryCompare(notch,"height",wideHeight);
        store.dismissCorrection();
        tryCompare(notch,"height",notch.maximumPanelHeight,1000,"The conversation keeps its existing height");
      } finally {assistant.visible=false;assistant.passive=false;}
    }
    function test_passive_correction_notch_does_not_claim_keyboard() {
      notch = create("../bar/BottomNotch.qml", window.contentItem,
        {calendar:calendar,assistant:assistant,panelWindow:null,monitorName:"eDP-1",availableWidth:1400,availableHeight:940,windowFocused:false});
      const source=Qt.createQmlObject('import QtQuick; TextInput { text: "Les fille" }',window.contentItem);
      try {
        source.forceActiveFocus();
        store.acceptLine(JSON.stringify({event:"correctionChanged",data:{id:"passive",provider:"qwen",state:"running",source:"Les fille"}}));
        assistant.passive=true;assistant.visible=true;
        tryVerify(()=>notch.active);wait(100);
        verify(source.activeFocus,"Opening the preview keeps focus in the source");
        verify(!notch.chatFocused);
        verify(notch.wantsKeyboard,"A deliberate click may focus the review for Enter/Escape");
      } finally {assistant.visible=false;assistant.passive=false;source.destroy();}
    }
  }
}
