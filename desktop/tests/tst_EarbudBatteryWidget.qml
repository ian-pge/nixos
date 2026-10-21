import QtQuick
import QtTest
import Quickshell

// Pure views with fictional readings: no Bluetooth or PipeWire operations.
ShellRoot {
  id: root
  property var theme: null
  property var block: null
  property var widget: null
  Window { id: window; visible: true; width: 240; height: 120 }
  Component.onCompleted: {
    theme = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../ui/Theme.js" as T; QtObject { property var library: T }', root).library;
    const prefix = "file://" + Quickshell.shellDir + "/../bar/";
    const b = Qt.createComponent(prefix + "BarBlock.qml"), w = Qt.createComponent(prefix + "EarbudBatteryWidget.qml");
    if (b.status !== Component.Ready || w.status !== Component.Ready) { console.error(b.errorString(), w.errorString()); Qt.exit(1); return; }
    block = b.createObject(window.contentItem, {x: 20, y: 20, circularContent: true});
    widget = w.createObject(block, {reading: reading(false)});
    block.content.push(widget);
  }
  function reading(connected) { return {name: "Pixel Buds", percent: 85, pluggedIn: false,
    warning: false, audioConnected: connected, tooltip: "Boîtier : 85%\nGauche : 100%\nDroite : 100%"}; }
  TestResult { id: results }
  TestCase {
    name: "EarbudBatteryWidget"
    when: root.widget !== null && window.visible
    function init() { widget.reading = root.reading(false); wait(20); }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function cleanupTestCase() {
      console.log("EarbudBatteryWidget: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_connection_check_never_changes_widget_width() {
      const badge = findChild(widget, "earbudAudioBadge"), dial = findChild(widget, "earbudBatteryPill");
      const originalWidth = widget.width, originalBlockWidth = block.width;
      verify(!badge.visible); compare(widget.width, theme.barSize(32));
      widget.reading = root.reading(true); wait(20);
      verify(badge.visible); compare(widget.width, dial.width);
      compare(widget.width, originalWidth); compare(block.width, originalBlockWidth);
      compare(findChild(badge, "dialBadgeIcon").name, "check");
      compare(badge.height, theme.barSize(10)); compare(badge.radius, badge.height / 2);
      compare(findChild(badge, "dialBadgeIcon").size, theme.barSize(7));
      compare(dial.width, theme.barSize(32)); compare(block.height, theme.barGroupHeight);
      verify(dial.tooltipText.endsWith("Audio connecté au PC"));
      compare(dial.value, 85); verify(!dial.pluggedIn);
      widget.reading = root.reading(false); wait(20);
      verify(!badge.visible); compare(widget.width, dial.width);
      compare(block.width, originalBlockWidth);
      compare(dial.tooltipText, widget.reading.tooltip);
    }
    function test_neighbour_keeps_the_same_position_and_spacing() {
      const row = Qt.createQmlObject('import QtQuick; Row {}', window.contentItem);
      row.spacing = theme.barSize(4);
      try {
        const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../bar/EarbudBatteryWidget.qml");
        const earbuds = component.createObject(row, {reading: root.reading(false)});
        const neighbour = Qt.createQmlObject('import QtQuick; Item {}', row);
        neighbour.width = theme.barSize(32); neighbour.height = neighbour.width;
        wait(20);
        const x = neighbour.x, width = row.width;
        for (const connected of [true, false, true, false]) {
          earbuds.reading = root.reading(connected); wait(20);
          compare(neighbour.x, x); compare(row.width, width);
          compare(neighbour.x - earbuds.width, theme.barSize(4));
        }
      } finally { row.destroy(); }
    }
    function test_check_does_not_replace_charge_or_low_battery_warning() {
      widget.reading = Object.assign(root.reading(true), {percent: null, warning: true, pluggedIn: true});
      const dial = findChild(widget, "earbudBatteryPill");
      verify(findChild(widget, "earbudAudioBadge").visible);
      verify(!dial.known); verify(dial.warning); verify(dial.pluggedIn);
      compare(dial.indicatorColor.toString(), "#ed8796");
    }
    function test_overlay_fits_inside_rounded_bubble_and_leaves_icon_center_clear() {
      widget.reading = root.reading(true); wait(20);
      const badge = findChild(widget, "earbudAudioBadge"), icon = findChild(widget, "dialIcon");
      const background = findChild(block, "barBlockBackground"), radius = background.radius;
      verify(badge.x >= icon.x + icon.width / 2);
      verify(badge.y + badge.height <= icon.y + icon.height / 3);
      verify(badge.x + badge.width <= widget.width);
      const r = badge.radius;
      for (const [cx, cy, start] of [[r,r,180],[badge.width-r,r,270],
          [badge.width-r,badge.height-r,0],[r,badge.height-r,90]]) {
        for (let angle = start; angle <= start+90; angle+=15) {
          const point = badge.mapToItem(background,cx+r*Math.cos(angle*Math.PI/180),cy+r*Math.sin(angle*Math.PI/180));
          const nearX=Math.max(radius,Math.min(background.width-radius,point.x));
          const nearY=Math.max(radius,Math.min(background.height-radius,point.y));
          verify(Math.hypot(point.x-nearX,point.y-nearY)<=radius+0.05);
        }
      }
    }
  }
}
