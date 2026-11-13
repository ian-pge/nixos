import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  Window { id: window; width: 1280; height: 900; visible: true }
  property var beeperData: null
  property var panel: null
  // The assistant service owns the engine; Beeper only receives this interface.
  QtObject {
    id: corrector
    property var calls: []
    property var completedStates: []
    property var proposal: null
    property var pendingCall: null
    property var decisions: []
    function correctText(text, callback, provider) { pendingCall={text:text,callback:callback,provider:provider};calls=calls.concat([pendingCall]);return "test-review"; }
    function decideCorrection(accept) { decisions=decisions.concat([accept]); if(!pendingCall || accept && !proposal)return; const call=pendingCall;pendingCall=null;call.callback(accept ? proposal : {cancelled:true},null);proposal=null; }
    function finishCorrection(result, state) { completedStates = completedStates.concat([state]); }
    function respond(result, error) {
      const call = calls[0]; calls = calls.slice(1);
      if(error){pendingCall=null;call.callback(null,error);}else proposal=result;
    }
  }
  TestResult { id: results }
  TestCase {
    name: "SpellingCorrection"
    when: window.visible
    function create(file, parent, props) {
      const c = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(c.status, Component.Ready, c.errorString());
      const item = c.createObject(parent, props); verify(item !== null); return item;
    }
    function init() {
      corrector.calls = []; corrector.completedStates = [];corrector.proposal=null;corrector.pendingCall=null;corrector.decisions=[];
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      beeperData.replaceChats([{id: "friend", title: "Friend"}]);
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, corrector: corrector, width: 1280, height: 900, active: true, windowFocused: true});
      beeperData.selectChat("friend"); beeperData.respond("messages", {items: []});
      window.requestActivate(); panel.compose(); tryVerify(() => panel.composer.activeFocus);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("SpellingCorrection: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function pending(method) { return beeperData.requests.filter(r => r.method === method); }
    function test_shortcuts_correct_and_restore_without_sending() {
      beeperData.draftText = "Les fille 😂"; panel.composer.cursorPosition = panel.composer.length;
      keyClick(Qt.Key_Tab, Qt.ControlModifier | Qt.AltModifier);
      compare(corrector.calls.length, 1); compare(corrector.calls[0].text, "Les fille 😂");
      compare(corrector.calls[0].provider, "qwen");
      corrector.respond({text: "Les filles 😂", edits: [{start:4,end:9,replacement:"filles"}]});
      compare(beeperData.draftText,"Les fille 😂");keyClick(Qt.Key_Return);
      compare(beeperData.draftText, "Les filles 😂"); compare(pending("send").length, 0);
      keyClick(Qt.Key_Tab, Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier);
      compare(beeperData.draftText, "Les fille 😂"); compare(pending("send").length, 0);
    }
    function test_selection_only_preserves_surrounding_text() {
      beeperData.draftText = "Début : les fille\nfin 🙂"; panel.composer.select(8, 17);
      panel.correctComposerSpelling(); compare(corrector.calls[0].text, "les fille");
      corrector.respond({text:"les filles",edits:[{start:4,end:9,replacement:"filles"}]});keyClick(Qt.Key_Return);
      compare(beeperData.draftText, "Début : les filles\nfin 🙂");
    }
    function test_changed_draft_or_focus_cancels_replacement_data() {
      return [{tag:"typing",kind:"typing"},{tag:"cursor",kind:"cursor"}];
    }
    function test_changed_draft_or_focus_cancels_replacement(test) {
      beeperData.draftText = "Les fille"; panel.composer.cursorPosition = 9; panel.correctComposerSpelling();
      if (test.kind === "typing") beeperData.draftText = "My new text";
      else if (test.kind === "focus") { panel.windowFocused = false; panel.windowFocused = true; }
      else panel.composer.cursorPosition = 0;
      const expected = beeperData.draftText;
      corrector.respond({text:"Les filles",edits:[{}]});keyClick(Qt.Key_Return);
      compare(beeperData.draftText, expected); verify(!panel.correctingSpelling); compare(pending("send").length, 0);
    }
    function test_failure_and_uncertainty_preserve_original() {
      beeperData.draftText = "salut tkt 😂"; panel.correctComposerSpelling();
      corrector.respond(null, {message:"Unavailable"}); compare(beeperData.draftText,"salut tkt 😂");
      panel.correctComposerSpelling(); corrector.respond({text:beeperData.draftText,edits:[],skipped:1});keyClick(Qt.Key_Return);
      compare(beeperData.draftText,"salut tkt 😂"); verify(!panel.correctingSpelling);
    }
    function test_missing_corrector_keeps_draft_and_explains() {
      panel.corrector = null; beeperData.draftText = "Les fille";
      panel.correctComposerSpelling();
      compare(panel.notice, "");
      compare(beeperData.draftText, "Les fille"); verify(!panel.correctingSpelling); compare(pending("send").length, 0);
    }
    function test_alt_tab_uses_gpt_and_emits_no_notice() {
      beeperData.draftText = "Les fille";
      keyClick(Qt.Key_Tab, Qt.AltModifier);
      compare(corrector.calls.length, 1); compare(corrector.calls[0].provider, "openai");
      corrector.respond({text:"Les filles",edits:[{start:4,end:9,replacement:"filles"}]});keyClick(Qt.Key_Return);
      compare(beeperData.draftText,"Les filles");compare(panel.notice,"");compare(corrector.completedStates,["applied"]);
    }
    function test_escape_dismisses_without_applying_or_sending() {
      beeperData.draftText="Les fille";panel.correctComposerSpelling();
      corrector.respond({text:"Les filles",edits:[{}]});
      keyClick(Qt.Key_Escape);
      compare(beeperData.draftText,"Les fille");verify(!panel.correctingSpelling);
      compare(pending("send").length,0);compare(corrector.decisions,[false]);
    }
  }
}
