import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var first: null
  property var second: null
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../shell/DimmingPolicy.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    first = component.createObject(fixture);
    second = component.createObject(fixture);
  }
  TestResult { id: results }
  TestCase {
    name: "DimmingPolicy"
    when: first !== null && second !== null
    function init() {
      for (const policy of [first, second]) {
        policy.centralMode = "workspaces"; policy.chatOpen = false;
        policy.specialWorkspaceOpen = false; policy.opaqueTheme = true;
      }
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function cleanupTestCase() {
      console.log("DimmingPolicy: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function test_explicit_central_exceptions_do_not_request_dimming() {
      for (const mode of ["workspaces", "volume", "brightness", "notification", "dictation", "media"]) {
        first.centralMode = mode; verify(!first.requested); verify(!first.shellBackdropWanted);
      }
      for (const mode of ["bluetooth", "wifi", "updates", "launcher", "audio", "calendar",
          "system", "storage", "future-panel"]) {
        first.centralMode = mode; verify(first.requested); verify(first.shellBackdropWanted);
      }
    }
    function test_exempt_modes_never_cancel_another_request() {
      for (const mode of ["workspaces", "volume", "brightness", "notification", "dictation", "media"]) {
        first.centralMode = mode;
        first.chatOpen = true;
        verify(first.requested); verify(first.shellBackdropWanted);
        first.specialWorkspaceOpen = true;
        verify(first.requested); verify(first.compositorOwnsBackdrop); verify(!first.shellBackdropWanted);
        first.chatOpen = false;
        verify(first.requested); verify(!first.shellBackdropWanted);
        first.specialWorkspaceOpen = false;
        verify(!first.requested);
      }
    }
    function test_closing_one_source_preserves_the_remaining_sources() {
      first.centralMode = "bluetooth"; first.chatOpen = true; first.specialWorkspaceOpen = true;
      verify(first.requested); verify(!first.shellBackdropWanted);
      first.centralMode = "workspaces";
      verify(first.requested);
      first.specialWorkspaceOpen = false;
      verify(first.requested); verify(first.shellBackdropWanted);
      first.chatOpen = false;
      verify(!first.requested); verify(!first.shellBackdropWanted);
    }
    function test_monitors_are_independent() {
      first.specialWorkspaceOpen = true; second.centralMode = "bluetooth";
      verify(first.requested && second.requested);
      verify(first.compositorOwnsBackdrop && !second.compositorOwnsBackdrop);
      verify(!first.shellBackdropWanted && second.shellBackdropWanted);
      second.centralMode = "volume";
      verify(first.requested && !second.requested);
    }
    function test_glass_does_not_receive_a_shell_backdrop() {
      first.chatOpen = true;
      verify(first.requested); verify(!first.shellSuppressed); verify(first.shellBackdropWanted);
      first.opaqueTheme = false;
      verify(first.requested); verify(first.shellSuppressed); verify(!first.shellBackdropWanted);
      first.specialWorkspaceOpen = true;
      verify(first.compositorOwnsBackdrop); verify(first.requested);
    }
  }
}
