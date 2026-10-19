import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var backdrop: null
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../bar/PanelBackdrop.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    backdrop = component.createObject(window.contentItem);
  }
  Window {
    id: window
    width: 400; height: 300; visible: true
    Rectangle { anchors.fill: parent; color: "white" }
    Rectangle { x: 10; y: 10; width: 80; height: 42; z: 1; color: "white" }
    Rectangle { x: 100; y: 80; width: 200; height: 180; z: 1; color: "white" }
  }
  TestResult { id: results }
  TestCase {
    name: "PanelBackdrop"
    when: fixture.backdrop !== null
    function cleanupTestCase() {
      console.log("PanelBackdrop: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function init() {
      backdrop.shown = false; backdrop.suppressed = false;
      tryVerify(() => backdrop.opacity === 0);
    }
    function test_geometry_and_no_input_capture() {
      compare(backdrop.dimAmount, 0.6);
      compare(backdrop.x, 0); compare(backdrop.y, 0);
      compare(backdrop.width, window.width); compare(backdrop.height, window.height);
      verify(!backdrop.enabled); verify(!backdrop.visible);
    }
    function test_reversible_fade_and_unmap_after_closing() {
      backdrop.shown = true;
      wait(60);
      verify(backdrop.opacity > 0 && backdrop.opacity < backdrop.dimAmount);
      const alpha = backdrop.opacity;
      backdrop.shown = false;
      fuzzyCompare(backdrop.opacity, alpha, 0.001);
      verify(backdrop.visible);
      tryCompare(backdrop, "visible", false, 1000);
      compare(backdrop.opacity, 0);
      backdrop.shown = true;
      tryCompare(backdrop, "opacity", backdrop.dimAmount, 1000);
    }
    function test_synchronous_handoffs_do_not_snap_the_opacity() {
      backdrop.shown = true;
      tryVerify(() => backdrop.opacity === backdrop.dimAmount);
      backdrop.shown = false; backdrop.shown = true;
      compare(backdrop.opacity, backdrop.dimAmount);
      wait(30);
      compare(backdrop.opacity, backdrop.dimAmount);
      backdrop.shown = false; backdrop.shown = true; backdrop.shown = false;
      compare(backdrop.opacity, backdrop.dimAmount);
      wait(60);
      verify(backdrop.opacity > 0 && backdrop.opacity < backdrop.dimAmount);
      tryCompare(backdrop, "visible", false, 1000);
    }
    function test_native_owner_hides_even_a_fading_shell_backdrop_immediately() {
      backdrop.shown = true;
      tryVerify(() => backdrop.opacity === backdrop.dimAmount);
      backdrop.suppressed = true; backdrop.shown = false;
      verify(!backdrop.visible, "Never leave a second fading overlay over a native special workspace");
      wait(60); verify(!backdrop.visible);
      tryVerify(() => backdrop.opacity === 0);
      backdrop.suppressed = false; backdrop.shown = true;
      tryVerify(() => backdrop.visible && backdrop.opacity > 0);
      tryVerify(() => backdrop.opacity === backdrop.dimAmount);
    }
    function test_background_is_uniformly_dimmed_including_between_bar_widgets() {
      backdrop.shown = true;
      tryCompare(backdrop, "opacity", 0.6, 1000);
      wait(30);
      const rendered = grabImage(window.contentItem);
      const sx = rendered.width / window.width, sy = rendered.height / window.height;
      function red(x, y) { return rendered.red(Math.floor(x * sx), Math.floor(y * sy)); }
      compare(red(20, 20), 255, "The bar widget itself remains bright");
      compare(red(200, 150), 255, "Foreground panels remain undimmed");
      for (const x of [2, 20, 380, 398]) {
        const level = red(x, 150);
        verify(level >= 100 && level <= 104, "60% black reaches both screen edges: " + level);
      }
      for (const y of [2, 20, 51, 52, 53, 150, 298]) {
        const level = red(380, y);
        verify(level >= 100 && level <= 104, "No clear strip or seam behind the bar at y=" + y);
      }
    }
  }
}
