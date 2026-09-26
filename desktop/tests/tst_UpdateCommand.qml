import QtQuick
import QtTest
import Quickshell

// Exercise the Process adapter with tiny fake shell commands only. Never run
// the actual checker, installer or cleaner, and never instantiate Polkit.
ShellRoot {
  id: fixture
  property var command: null
  property var lines: []
  property var completions: []
  property bool ready: false
  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        || !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
      Qt.callLater(() => Qt.exit(1));
      return;
    }
    const type = Qt.createComponent("file://" + Quickshell.shellDir
      + "/../features/updates/UpdateCommand.qml");
    if (type.status !== Component.Ready) {
      console.error(type.errorString()); Qt.callLater(() => Qt.exit(1)); return;
    }
    command = type.createObject(fixture);
    command.lineRead.connect((line, generation) => {
      fixture.lines = fixture.lines.concat([{line, generation}]);
    });
    command.finished.connect((exitCode, exitStatus, output, generation) => {
      fixture.completions = fixture.completions.concat([{exitCode, exitStatus, output, generation}]);
    });
    ready = true;
  }
  TestResult { id: results }
  TestCase {
    name: "UpdateCommand"
    when: fixture.ready
    function cleanupTestCase() {
      console.log("UpdateCommand: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function init() { fixture.lines = []; fixture.completions = []; command.captureOutput = false; }
    function test_stdout_finishes_before_completion_and_resets_each_run() {
      command.captureOutput = true;
      command.exec(["sh", "-c", "printf 'first\\nsecond\\n'"], 20);
      tryCompare(fixture, "completions", [{exitCode: 0, exitStatus: 0, output: "first\nsecond\n", generation: 20}], 3000);
      compare(fixture.lines.length, 2);
      compare(fixture.lines[1].generation, 20);
      fixture.completions = [];
      command.exec(["sh", "-c", "printf 'next\\n'"], 21);
      tryCompare(fixture, "completions", [{exitCode: 0, exitStatus: 0, output: "next\n", generation: 21}], 3000);
    }
    function test_stdin_confirmation_and_non_captured_log() {
      command.exec(["sh", "-c", "IFS= read -r answer; printf '%s\\n' \"$answer\""], 30);
      tryCompare(command, "running", true);
      command.write("install\n");
      tryCompare(fixture, "completions", [{exitCode: 0, exitStatus: 0, output: "", generation: 30}], 3000);
      compare(fixture.lines[0].line, "install");
    }
    function test_failed_launch_finishes_instead_of_staying_busy() {
      command.exec(["/__quickshell_test_missing_update_helper__"], 40);
      tryVerify(() => fixture.completions.length === 1, 3000);
      verify(fixture.completions[0].exitCode !== 0 || fixture.completions[0].exitStatus !== 0);
      compare(fixture.completions[0].generation, 40);
      verify(!command.running);
    }
  }
}
