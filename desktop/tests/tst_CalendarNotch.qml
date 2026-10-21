import QtQuick
import QtTest
import Quickshell

// Actual compact bottom notch, with a clock/weather fixture and no services.
ShellRoot {
  id: root
  property var theme: null
  property var notch: null
  property int clicks: 0
  QtObject {
    id: weather
    property var days: ({"2026-10-21": {code: 61}})
    property string temperatureText: "11°"
  }
  QtObject {
    id: controller
    property date today: new Date(2026, 9, 21, 12)
    property string timeText: "12:00"
    property var weather: weather
  }
  Window { id: window; visible: true; width: 600; height: 120 }
  Component.onCompleted: {
    theme = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../ui/Theme.js" as T; QtObject { property var library: T }', root).library;
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../bar/CalendarNotch.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    notch = component.createObject(window.contentItem,
      {controller: controller, attachedToTop: false, attachedToBottom: true, x: 100, y: 60});
    notch.clicked.connect(() => root.clicks++);
  }
  TestResult { id: results }
  TestCase {
    name: "CalendarNotch"
    when: root.notch !== null && window.visible
    function cleanupTestCase() {
      console.log("CalendarNotch: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function test_selected_compact_design_and_cyan_palette() {
      compare(notch.height, root.theme.barGroupHeight); compare(notch.corner, root.theme.barGroupHeight / 2);
      compare(notch.accent.toString(), "#00f5ff");
      const time = findChild(notch, "timePill"), label = findChild(time, "notchLabel");
      compare(time.height, root.theme.barSize(19.2)); compare(time.color, notch.accent);
      compare(label.color.toString(), "#000000"); compare(label.font.pixelSize, root.theme.barSize(14.4)); verify(label.font.bold);
      verify(notch.dateText.startsWith("me "));
      for (const [name, size] of [["datePill", root.theme.barSize(11.2)], ["weatherPill", root.theme.barSize(12)]]) {
        const text = findChild(findChild(notch, name), "notchLabel");
        compare(text.font.pixelSize, size); verify(!text.font.bold);
      }
    }
    function test_all_readings_fit_on_one_low_row() {
      controller.timeText = "23:59"; weather.temperatureText = "−12°";
      wait(20);
      let previousEnd = 0;
      for (const name of ["datePill", "timePill", "weatherPill"]) {
        const cell = findChild(notch, name), position = cell.mapToItem(notch, 0, 0);
        verify(position.x > previousEnd);
        verify(position.y >= 0 && position.y + cell.height <= notch.height);
        verify(position.x + cell.width <= notch.width - notch.corner);
        previousEnd = position.x + cell.width;
      }
      compare(notch.height, root.theme.barGroupHeight);
    }
    function test_cells_keep_one_click_target() {
      for (const name of ["datePill", "timePill", "weatherPill"]) {
        const cell = findChild(notch, name), before = root.clicks;
        mouseMove(cell, cell.width/2, cell.height/2);
        tryCompare(notch, "hovered", true);
        mouseClick(cell);
        compare(root.clicks, before + 1);
      }
    }
    function test_hour_is_centered_with_symmetric_sides_and_round_ends() {
      const time = findChild(notch, "timePill"), date = findChild(notch, "datePill");
      const weatherCell = findChild(notch, "weatherPill");
      for (const [month, day, temperature] of [[9, 21, "11°"], [10, 29, "−12°"], [11, 31, "—"]]) {
        controller.today = new Date(2026, month, day, 12);
        weather.temperatureText = temperature;
        wait(20);
        const timeCenter = time.mapToItem(notch, time.width/2, time.height/2);
        const dateCenter = date.mapToItem(notch, date.width/2, date.height/2);
        const weatherCenter = weatherCell.mapToItem(notch, weatherCell.width/2, weatherCell.height/2);
        fuzzyCompare(timeCenter.x, notch.width/2, 0.01);
        fuzzyCompare(timeCenter.x - dateCenter.x, weatherCenter.x - timeCenter.x, 0.01);
        compare(time.radius, time.height/2);
        compare(notch.height, root.theme.barGroupHeight);
      }
      controller.today = new Date(2026, 9, 21, 12);
      weather.temperatureText = "11°";
    }
  }
}
