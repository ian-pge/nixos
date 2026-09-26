import QtQuick
import QtTest
import Quickshell

ShellRoot {
  property var wheel: null
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../ui/AcceleratedScroll.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    wheel = component.createObject(list, {flickable: list});
  }
  Window {
    id: window; visible: true; width: 600; height: 600
    Flickable {
      id: list; anchors.fill: parent; contentHeight: 12000
      boundsBehavior: Flickable.StopAtBounds; acceptedButtons: Qt.NoButton
    }
  }
  TestResult { id: results }
  TestCase {
    name: "AcceleratedScroll"
    when: window.visible && wheel !== null
    function init() { list.cancelFlick(); wheel.reset(); list.contentY = 2000; }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function cleanupTestCase() {
      console.log("Wheel tuning: " + wheel.step + " px/notch, " + wheel.duration + " ms, no cadence multiplier");
      console.log("AcceleratedScroll: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_fast_burst_accumulates_without_an_artificial_multiplier() {
      for (let i = 0; i < 5; ++i) wheel.scroll(-1, 1000 + i * 25);
      compare(wheel.destination, 2000 + 5 * wheel.step);
      compare(wheel.duration, 150);
      verify(wheel.driving); verify(!list.flicking);
      tryCompare(wheel, "driving", false, 700);
      fuzzyCompare(list.contentY, 2000 + 5 * wheel.step, 0.1);
    }
    function test_reversal_and_pause_drop_old_queued_distance() {
      for (let i = 0; i < 4; ++i) wheel.scroll(-1, 1000 + i * 20);
      wheel.scroll(1, 1100);
      compare(wheel.destination, list.contentY - wheel.step);
      wheel.scroll(-1, 2000);
      compare(wheel.destination, list.contentY + wheel.step);
    }
    function test_coordinate_shift_preserves_the_inflight_destination() {
      wheel.scroll(-1, 1000);
      const oldTarget = wheel.destination, oldY = list.contentY;
      wheel.shiftOrigin(300);
      compare(wheel.destination, oldTarget + 300); compare(list.contentY, oldY + 300);
      tryCompare(wheel, "driving", false, 700);
      fuzzyCompare(list.contentY, oldTarget + 300, 0.1);
    }
    function test_native_wheel_moves_but_ctrl_wheel_is_not_intercepted() {
      mouseWheel(list, 200, 200, 0, -120, Qt.NoButton, Qt.NoModifier);
      tryVerify(() => list.contentY > 2000);
      list.cancelFlick(); wheel.reset();
      mouseWheel(list, 200, 200, 0, -120, Qt.NoButton, Qt.ControlModifier);
      verify(!wheel.driving);
    }
    function test_bounds_and_accumulation_are_capped() {
      list.contentY = 0; wheel.scroll(30, 1000); compare(wheel.destination, 0);
      wheel.reset(); list.contentY = 11380; wheel.scroll(-30, 2000);
      compare(wheel.destination, list.contentHeight - list.height);
    }
    function test_wheel_still_works_when_a_scrollview_disables_mouse_dragging() {
      list.interactive = false;
      try {
        mouseWheel(list, 200, 200, 0, -120, Qt.NoButton, Qt.NoModifier);
        tryVerify(() => list.contentY > 2000);
      } finally { list.interactive = true; }
    }
  }
}
