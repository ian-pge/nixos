import QtQuick
import QtTest
import Quickshell

// All helpers and the authentication service are inert QML fakes. No native
// PolkitAgent is created and no check/build/install/cleanup command is started.
ShellRoot {
  id: fixture
  property var updates: null
  property var auth: null
  property var view: null
  property var events: []
  property bool ready: false

  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        || !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
      Qt.callLater(() => Qt.exit(1));
      return;
    }
    const directory = "file://" + Quickshell.shellDir + "/../features/";
    const updateType = Qt.createComponent(directory + "updates/UpdateController.qml");
    const authType = Qt.createComponent(directory + "auth/PolkitController.qml");
    const viewType = Qt.createComponent(directory + "updates/UpdateSelector.qml");
    for (const type of [updateType, authType, viewType]) {
      if (type.status !== Component.Ready) {
        console.error(type.errorString());
        Qt.callLater(() => Qt.exit(1));
        return;
      }
    }
    updates = updateType.createObject(fixture, {autoCheckEnabled: false,
      operationProcess: operationRunner, statusProcess: statusRunner});
    auth = authType.createObject(fixture, {serviceEnabled: false, agent: fakeAgent});
    view = viewType.createObject(window.contentItem, {updates, auth,
      width: 480, height: 300, enabled: false, visible: false});
    updates.presentationRequested.connect(() => fixture.events.push("present"));
    updates.closeRequested.connect(() => fixture.events.push("close-update"));
    auth.requestStarted.connect(() => fixture.events.push("auth-start"));
    auth.requestFinished.connect(() => fixture.events.push("auth-finish"));
    view.closeRequested.connect(() => fixture.events.push("close-view"));
    ready = true;
  }

  Window { id: window; width: 480; height: 300; visible: true }
  component FakeRunner: QtObject {
    property bool running: false
    property int generation: 0
    property var commands: []
    property var writes: []
    signal lineRead(string line, int generation)
    signal finished(int exitCode, int exitStatus, string output, int generation)
    function exec(command, token) {
      running = true;
      generation = token;
      commands = commands.concat([command]);
    }
    function write(text) { writes = writes.concat([text]); }
    function emitEvent(value) { lineRead("@@QS_UPDATE@@" + JSON.stringify(value), generation); }
    function finish(code = 0, output = "", status = 0) {
      running = false;
      finished(code, status, output, generation);
    }
    function reset() { running = false; commands = []; writes = []; }
  }
  FakeRunner { id: operationRunner }
  FakeRunner { id: statusRunner }
  component FakeFlow: QtObject {
    property string message: "Authenticate to manage a device"
    property string inputPrompt: "Password"
    property string supplementaryMessage: ""
    property bool supplementaryIsError: false
    property bool responseVisible: false
    property bool isResponseRequired: true
    property var responses: []
    property int cancelled: 0
    signal authenticationFailed()
    signal authenticationRequestCancelled()
    function submit(response) { responses = responses.concat([response]); }
    function cancelAuthenticationRequest() { ++cancelled; authenticationRequestCancelled(); }
  }
  FakeFlow { id: firstFlow }
  FakeFlow { id: secondFlow }
  QtObject {
    id: fakeAgent
    property bool isActive: false
    property var flow: null
    signal authenticationRequestStarted()
  }

  TestResult { id: results }
  TestCase {
    name: "UpdateControllers"
    when: fixture.ready
    function cleanupTestCase() {
      console.log("UpdateControllers: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      view.enabled = false; view.visible = false;
    }
    function init() {
      fakeAgent.isActive = false; fakeAgent.flow = null;
      firstFlow.isResponseRequired = true; firstFlow.responses = []; firstFlow.cancelled = 0;
      secondFlow.responses = [];
      auth.clearInput();
      operationRunner.reset(); statusRunner.reset();
      updates.operationRunning = false; updates.statusRunning = false;
      updates.checking = false; updates.checkFailed = false; updates.statusKnown = false;
      updates.rebootRequired = false; updates.phase = "idle";
      updates.operation = "update"; updates.message = ""; updates.awaitingPolkit = false;
      updates.refreshPending = false; updates.resetSummary();
      updates.updates = [{name: "nixpkgs", date: "2026-09-25"}];
      fixture.events = [];
    }
    function beginAuth(flow = firstFlow) {
      fakeAgent.flow = flow;
      fakeAgent.isActive = true;
      fakeAgent.authenticationRequestStarted();
    }
    function statusResult(state = "updates", list = [{name: "nixpkgs", date: "today"}]) {
      return JSON.stringify({state, updates: list, hasUpdates: list.length > 0});
    }
    function showView() {
      view.visible = true; view.enabled = true; view.forceActiveFocus();
      wait(10); verify(view.activeFocus);
    }
    function test_disabled_startup_is_inert() {
      compare(operationRunner.commands.length, 0);
      compare(statusRunner.commands.length, 0);
      verify(!auth.active);
      verify(!auth.serviceEnabled);
    }
    function test_enabled_startup_uses_injected_checker_only() {
      const type = Qt.createComponent("file://" + Quickshell.shellDir
        + "/../features/updates/UpdateController.qml");
      const controller = type.createObject(fixture, {autoCheckEnabled: true,
        operationProcess: operationRunner, statusProcess: statusRunner});
      compare(statusRunner.commands.length, 1);
      compare(statusRunner.commands[0][0], "quickshell-update-checker");
      verify(controller.checking);
      statusRunner.finish(0, statusResult());
      verify(!controller.checking);
      compare(controller.updates.length, 1);
      controller.destroy();
    }
    function test_build_and_summary_never_install_without_confirmation() {
      verify(updates.startUpdate());
      compare(fixture.events.join(","), "present");
      compare(operationRunner.commands[0][0], "quickshell-update-installer");
      verify(updates.busy);
      updates.installUpdate();
      compare(operationRunner.writes.length, 0);
      operationRunner.emitEvent({phase: "building", message: "Building"});
      operationRunner.emitEvent({phase: "awaitingInstall", changes: [{name: "app", kind: "added", oldVersions: [], newVersions: ["1"]}], counts: {added: 1}});
      verify(!updates.busy); verify(updates.summaryReady);
      compare(updates.changes.length, 1);
      compare(updates.displayedIcon, "󰌾");
      compare(operationRunner.writes.length, 0);
      updates.handleEnter();
      compare(operationRunner.writes.join(""), "install\n");
      verify(updates.awaitingPolkit);
      compare(updates.phase, "preparingAuth");
      updates.handleEnter(); updates.installUpdate();
      compare(operationRunner.writes.length, 1);
    }
    function test_operations_are_mutually_exclusive_even_awaiting_install() {
      updates.startUpdate();
      operationRunner.emitEvent({phase: "awaitingInstall"});
      verify(!updates.startClean()); verify(!updates.startUpdate());
      verify(!updates.refreshStatus()); verify(!updates.forceStatus());
      compare(operationRunner.commands.length, 1);
      compare(statusRunner.commands.length, 0);
      operationRunner.finish(1);
      verify(updates.startClean());
      verify(!updates.startUpdate());
      compare(operationRunner.commands[1][0], "quickshell-nix-cleaner");
      verify(updates.awaitingPolkit);
    }
    function test_terminal_early_exit_and_retry() {
      updates.startUpdate(); operationRunner.emitEvent({phase: "awaitingInstall"});
      operationRunner.finish();
      compare(updates.phase, "error");
      compare(updates.message, "The update stopped unexpectedly");
      verify(!updates.awaitingPolkit);
      updates.handleEnter();
      compare(updates.phase, "updating");
      compare(operationRunner.commands.length, 2);
      operationRunner.finish(9);
      compare(updates.message, "The update process exited with code 9");
    }
    function test_cleanup_error_then_success_refreshes_status() {
      updates.startClean();
      operationRunner.emitEvent({phase: "error", message: "Authorization denied"});
      operationRunner.finish(1);
      compare(updates.message, "Authorization denied");
      verify(!updates.awaitingPolkit);
      updates.handleEnter();
      operationRunner.emitEvent({phase: "success", message: "Cleanup complete"});
      verify(!updates.rebootRequired);
      compare(statusRunner.commands.length, 0);
      operationRunner.finish();
      compare(statusRunner.commands.length, 1);
      statusRunner.finish(0, statusResult("current", []));
      updates.handleEnter();
      compare(updates.phase, "idle");
      compare(fixture.events.join(","), "present,present,close-update");
    }
    function test_success_reboot_marker_survives_failed_checker() {
      updates.startUpdate();
      operationRunner.emitEvent({phase: "success"});
      verify(updates.rebootRequired);
      operationRunner.finish();
      statusRunner.finish(1);
      verify(updates.checkFailed); verify(updates.rebootRequired);
      verify(!updates.startUpdate());
    }
    function test_stale_generation_cannot_finish_or_overwrite_new_operation() {
      updates.startUpdate(); const oldGeneration = operationRunner.generation;
      operationRunner.finish(1); updates.startClean();
      operationRunner.lineRead('@@QS_UPDATE@@{"phase":"success"}', oldGeneration);
      operationRunner.finished(0, 0, "", oldGeneration);
      compare(updates.phase, "cleaning"); verify(updates.operationRunning);
      operationRunner.lineRead('@@QS_UPDATE@@{"phase":"awaitingInstall"}', operationRunner.generation);
      compare(updates.phase, "cleaning");
      operationRunner.emitEvent({phase: "error", message: "Failed"});
      operationRunner.emitEvent({phase: "success"});
      compare(updates.phase, "error");
    }
    function test_checker_serialization_failures_and_cached_status() {
      verify(updates.refreshStatus()); verify(updates.checking);
      verify(!updates.forceStatus()); verify(!updates.startClean());
      statusRunner.finish(0, statusResult("reboot-required", []));
      verify(updates.rebootRequired); compare(updates.icon, "󰜉");
      verify(updates.refreshStatus()); verify(!updates.checking);
      statusRunner.finish(0, "malformed");
      verify(updates.checkFailed); verify(updates.rebootRequired);
      verify(updates.forceStatus()); verify(updates.checking);
      compare(statusRunner.commands[2][1], "force");
      statusRunner.finish(0, statusResult("current", []));
      verify(!updates.rebootRequired); verify(!updates.checkFailed);
      updates.handleEnter(); compare(fixture.events.join(","), "close-update");
    }
    function test_auth_lifecycle_clears_challenges_and_submitted_secret() {
      beginAuth(); compare(fixture.events.join(","), "auth-start");
      auth.appendInput("secret"); auth.eraseInput(); compare(auth.input, "secre");
      auth.submitResponse(); compare(auth.input, "");
      compare(firstFlow.responses.join(","), "secre");
      auth.appendInput("retry"); firstFlow.authenticationFailed(); compare(auth.input, "");
      auth.appendInput("pending"); firstFlow.isResponseRequired = false;
      compare(auth.input, ""); auth.appendInput("ignored"); auth.submitResponse();
      compare(auth.input, ""); compare(firstFlow.responses.length, 1);
      fakeAgent.isActive = false;
      compare(fixture.events.join(","), "auth-start,auth-finish");
      verify(!auth.active);
    }
    function test_auth_replacement_cannot_reuse_previous_secret() {
      beginAuth(); auth.appendInput("not-for-next-flow");
      fakeAgent.flow = secondFlow;
      compare(auth.input, "");
      compare(fixture.events.join(","), "auth-start,auth-finish,auth-start");
      auth.appendInput("new"); auth.submitResponse();
      compare(firstFlow.responses.length, 0); compare(secondFlow.responses.join(","), "new");
      auth.appendInput("discard"); auth.cancelRequest();
      compare(auth.input, ""); compare(secondFlow.cancelled, 1);
    }
    function test_view_auth_keyboard_hides_without_cancelling_request() {
      beginAuth(); showView();
      keyClick(Qt.Key_A); keyClick(Qt.Key_B); keyClick(Qt.Key_Backspace);
      compare(auth.input, "a");
      keyClick(Qt.Key_Return); compare(firstFlow.responses.join(","), "a");
      compare(operationRunner.commands.length, 0);
      keyClick(Qt.Key_C); keyClick(Qt.Key_U, Qt.ControlModifier); compare(auth.input, "");
      keyClick(Qt.Key_D); keyClick(Qt.Key_Escape);
      compare(auth.input, ""); verify(auth.active); compare(firstFlow.cancelled, 0);
      compare(fixture.events.join(","), "auth-start,close-view");
    }
    function test_view_update_keys_route_to_narrow_controller() {
      showView();
      keyClick(Qt.Key_Return); compare(updates.phase, "updating");
      operationRunner.emitEvent({phase: "awaitingInstall", changes: [{name: "test", oldVersions: [], newVersions: ["1"], kind: "added"}]});
      keyClick(Qt.Key_J); keyClick(Qt.Key_K);
      compare(operationRunner.writes.length, 0);
      keyClick(Qt.Key_Return); compare(operationRunner.writes.join(""), "install\n");
      keyClick(Qt.Key_Escape); compare(fixture.events.join(","), "present,close-view");
      verify(updates.operationRunning);
    }
  }
}
