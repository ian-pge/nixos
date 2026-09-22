import Quickshell
import QtQuick
import QtTest
import "components"
import "components/Theme.js" as Theme

// Run explicitly with the offscreen platform; the normal shell never loads it.
ShellRoot {
  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") Qt.exit(1);
  }
  Window {
    id: testWindow
    visible: true
    width: 320
    height: 150

    Pill {
      id: pill
      x: 10; y: 10; width: 260; height: 36
      text: "Volume"
      trailingText: "Micro"
      accent: Theme.sideVolume
      interactive: true
    }
  }

  TestResult { id: results }
  SignalSpy { id: clicks; target: pill; signalName: "leftClicked" }
  TestCase {
    name: "Pill"
    when: testWindow.visible

    function initTestCase() {
      // Let the (stubbed) compositor probe finish before overriding its state.
      wait(200);
    }
    function init() {
      mouseMove(testWindow.contentItem, 310, 140);
      pill.forceHovered = false;
      pill.trailingInactive = false;
      GlassState.enabled = false;
      clicks.clear();
      wait(250);
    }
    function cleanupTestCase() {
      console.log("Pill: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount > 0 ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function background() { return findChild(pill, "pill-background"); }
    function label() { return findChild(pill, "pill-label"); }
    function trailing() { return findChild(pill, "pill-trailing-label"); }
    function test_active_data() {
      return [{tag: "glass", glass: true}, {tag: "opaque fallback", glass: false}];
    }
    function test_active(data) {
      GlassState.enabled = data.glass;
      pill.forceHovered = true;
      wait(250);
      verify(pill.hovered);
      const tint = Qt.alpha(pill.accent, 0.16);
      compare(background().color, data.glass ? tint : Qt.tint(Theme.background, tint));
      compare(label().color, pill.accent);
      compare(trailing().color, pill.accent);
      if (data.glass) verify(background().color.a < 0.2);
      else compare(background().color.a, 1);
      compare(pill.width, 260);
      compare(pill.height, 36);
    }
    function test_hover_and_click_keep_the_same_light_tint() {
      GlassState.enabled = true;
      mouseMove(pill, 100, 18);
      tryCompare(pill, "hovered", true);
      wait(250);
      compare(background().color, Qt.alpha(pill.accent, 0.16));
      compare(label().color, pill.accent);
      mouseClick(pill, 100, 18);
      compare(clicks.count, 1);
      mouseMove(testWindow.contentItem, 310, 140);
      tryCompare(pill, "hovered", false);
      wait(250);
      compare(background().color, Qt.alpha(Theme.background, 0.12));
    }
    function test_inactive_trailing_label_stays_muted() {
      GlassState.enabled = true;
      pill.forceHovered = true;
      pill.trailingInactive = true;
      wait(250);
      compare(label().color, pill.accent);
      compare(trailing().color, Theme.inactive);
    }
  }
}
