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
    function wheelEvent(angle, pixels, phase = Qt.NoScrollPhase, device = PointerDevice.Mouse) {
      return {angleDelta: Qt.point(0, angle), pixelDelta: Qt.point(0, pixels),
        phase: phase, device: {type: device}, accepted: false};
    }
    function test_wayland_mouse_pixels_do_not_cancel_the_wheel_animation() {
      // Actual Wayland packets carry -120 angle units AND -15 pixels per
      // notch. QtTest.mouseWheel only supplies angles and missed this failure.
      for (let i = 0; i < 8; ++i) {
        const event = wheelEvent(-120, -15, Qt.NoScrollPhase, PointerDevice.TouchPad);
        wheel.handleWheel(event);
        verify(event.accepted);
        verify(wheel.driving);
        wait(30);
      }
      tryCompare(wheel, "driving", false, 700);
      fuzzyCompare(list.contentY, 2000 + 8 * wheel.step, 0.1);
    }
    function test_high_resolution_mouse_preserves_fractional_notches() {
      for (let i = 0; i < 16; ++i) {
        wheel.handleWheel(wheelEvent(-15, -2));
        wait(8);
      }
      tryCompare(wheel, "driving", false, 700);
      fuzzyCompare(list.contentY, 2000 + 2 * wheel.step, 0.1);
    }
    function test_touchpad_and_pixel_only_gestures_keep_the_native_path() {
      for (const event of [wheelEvent(-120, -15, Qt.ScrollUpdate),
        wheelEvent(-120, -15, Qt.ScrollUpdate, PointerDevice.TouchPad),
        wheelEvent(0, -15)]) {
        wheel.handleWheel(event);
        verify(!event.accepted);
        verify(!wheel.driving);
        compare(list.contentY, 2000);
      }
    }
    function test_empty_and_horizontal_packets_keep_pending_vertical_travel() {
      wheel.handleWheel(wheelEvent(-120, -15));
      const target = wheel.destination;
      for (const event of [wheelEvent(0, 0),
        {angleDelta: Qt.point(120, 0), pixelDelta: Qt.point(15, 0), accepted: false}]) {
        wheel.handleWheel(event);
        verify(!event.accepted); verify(wheel.driving);
        compare(wheel.destination, target);
      }
      tryCompare(wheel, "driving", false, 700);
      fuzzyCompare(list.contentY, target, 0.1);
    }
  }
}
