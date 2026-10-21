import QtQuick
import QtTest
import Quickshell

// The real bar view with inert providers: no CLI, account or network access.
ShellRoot {
  id: root
  readonly property real start: Date.UTC(2026, 9, 21, 8, 0)
  property var block: null
  property var theme: null
  Component.onCompleted: {
    theme = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../ui/Theme.js" as T; QtObject { property var library: T }', root).library;
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../bar/UsageBlock.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString()); Qt.exit(1); return;
    }
    block = component.createObject(window.contentItem, {x: 10, y: 10, controller: controller});
  }
  QtObject {
    id: claudeSource
    property string name: "Claude"
    property var snapshot: null
    property string error: ""
    property bool loading: false
    property real updatedAt: root.start
  }
  QtObject {
    id: codexSource
    property string name: "Codex"
    property var snapshot: null
    property string error: ""
    property bool loading: false
    property real updatedAt: root.start
  }
  QtObject {
    id: controller
    property var claude: claudeSource
    property var codex: codexSource
    property real now: root.start
  }
  Window {
    id: window
    visible: true
    width: 300; height: 150
  }
  TestResult { id: results }
  TestCase {
    name: "UsageBlock"
    when: window.visible && root.block !== null
    function cleanupTestCase() {
      console.log("UsageBlock: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function init() {
      controller.now = root.start;
      codexSource.snapshot = {resetCredits: 0, limits: [
        {minutes: 10080, percent: 20, resetsAt: root.start + (2 * 1440 + 4 * 60 + 8) * 60000}]};
      claudeSource.snapshot = {resetCredits: 1, limits: [
        {window: "five_hour", percent: 10, resetsAt: root.start + (4 * 60 + 5) * 60000},
        {window: "seven_day", percent: 30, resetsAt: root.start + 1440 * 60000}]};
      wait(0);
    }
    function countdown(name) { return findChild(block, name + "Countdown"); }
    function test_each_dial_uses_its_own_reset() {
      compare(countdown("gptUsageDial").text, "2 j");
      compare(countdown("claudeFiveHourDial").text, "4h05");
      compare(countdown("claudeWeeklyDial").text, "1 j");
      verify(findChild(findChild(block, "claudeWeeklyDial"), "resetCreditsBadge").visible);
      verify(!findChild(findChild(block, "claudeFiveHourDial"), "resetCreditsBadge").visible);
      compare(block.height, root.theme.barGroupHeight, "Keep every quota on one row");
      const rows = new Set();
      for (const name of ["gptUsageDial", "claudeFiveHourDial", "claudeWeeklyDial"]) {
        const text = countdown(name), dial = findChild(block, name);
        compare(text.font.pixelSize, root.theme.barSize(16));
        compare(text.fontSizeMode, Text.FixedSize);
        compare(dial.scale, 1, "Usage icons keep the standard BarDial size");
        compare(dial.width, root.theme.barSize(32)); compare(dial.height, root.theme.barSize(32));
        const position = text.mapToItem(block, 0, 0);
        tryVerify(() => text.width > 0 && text.contentWidth <= text.width, 1000,
          name + " text must fit");
        verify(position.x >= dial.mapToItem(block, dial.width, 0).x);
        const badge = findChild(dial, "resetCreditsBadge");
        if (badge.visible)
          verify(position.x >= badge.mapToItem(block, badge.width, 0).x + root.theme.barSize(2),
            "Countdown and reset badge must not overlap");
        fuzzyCompare(position.y + text.height / 2,
          dial.mapToItem(block, 0, dial.height / 2).y, 0.5);
        verify(position.x + text.width <= block.width);
        verify(position.y >= 0 && position.y + text.height <= block.height);
        rows.add(position.y);
      }
      compare(rows.size, 1);
    }
    function test_clock_tick_and_new_snapshot_update_the_text() {
      controller.now += 60000;
      compare(countdown("gptUsageDial").text, "2 j");
      compare(countdown("claudeFiveHourDial").text, "4h04");
      compare(countdown("claudeWeeklyDial").text, "23h59");
      tryVerify(() => countdown("claudeWeeklyDial").contentWidth <= countdown("claudeWeeklyDial").width,
        1000, "The longest hour/minute reading fits to the right of the icon");
      codexSource.snapshot = {limits: [{minutes: 10080, percent: 0, resetsAt: controller.now + 60000}]};
      compare(countdown("gptUsageDial").text, "1 min");
      controller.now += 60000;
      compare(countdown("gptUsageDial").text, "");
      verify(!countdown("gptUsageDial").visible);
    }
    function test_failed_reset_read_has_an_explicit_unknown_badge() {
      claudeSource.snapshot = Object.assign({}, claudeSource.snapshot,
        {resetCredits: null, resetCreditsUnavailable: true});
      const weekly = findChild(block, "claudeWeeklyDial");
      verify(findChild(weekly, "resetCreditsBadge").visible);
      compare(findChild(weekly, "resetCreditsCount").text, "?");
      verify(weekly.tooltipText.includes("vérification temporairement indisponible"));
      verify(!findChild(findChild(block, "claudeFiveHourDial"), "resetCreditsBadge").visible);
      claudeSource.snapshot = Object.assign({}, claudeSource.snapshot,
        {resetCredits: 1, resetCreditsUnavailable: false});
      compare(findChild(weekly, "resetCreditsCount").text, "1");
      verify(!weekly.tooltipText.includes("indisponible"));
    }
    function test_reset_badges_stay_inside_the_rounded_widget() {
      for (const count of [1, 12, null]) {
        // No countdown on the last dial: its badge is next to the rounded end.
        claudeSource.snapshot = {resetCredits: count, resetCreditsUnavailable: count === null,
          limits: [{window: "seven_day", percent: 0, resetsAt: null}]};
        codexSource.snapshot = {resetCredits: count, resetCreditsUnavailable: count === null,
          limits: [{minutes: 10080, percent: 0, resetsAt: null}]};
        wait(20);
        const background = findChild(block, "barBlockBackground"), radius = background.radius;
        for (const name of ["gptUsageDial", "claudeWeeklyDial"]) {
          const dial = findChild(block, name), logo = findChild(dial, "dialLogo");
          const badge = findChild(dial, "resetCreditsBadge"), r = badge.radius;
          verify(badge.visible);
          compare(badge.x + badge.width, dial.width - root.theme.barSize(3));
          compare(badge.y, root.theme.barSize(2));
          compare(badge.height, root.theme.barSize(10));
          verify(badge.y + badge.height <= logo.y + logo.height / 2,
            "Overlay leaves the centre of the provider logo clear");
          const label = findChild(badge, "resetCreditsCount");
          verify(label.implicitWidth <= badge.width - root.theme.barSize(2),
            "Multiple-digit counts remain readable inside the badge");
          for (const [cx, cy, start] of [[r, r, 180], [badge.width-r, r, 270],
              [badge.width-r, badge.height-r, 0], [r, badge.height-r, 90]]) {
            for (let angle = start; angle <= start + 90; angle += 15) {
              const point = badge.mapToItem(background,
                cx + r * Math.cos(angle * Math.PI / 180), cy + r * Math.sin(angle * Math.PI / 180));
              verify(point.x >= 0 && point.x <= background.width && point.y >= 0 && point.y <= background.height,
                JSON.stringify({name, count, point, width: background.width, height: background.height}));
              const nearestX = Math.max(radius, Math.min(background.width-radius, point.x));
              const nearestY = Math.max(radius, Math.min(background.height-radius, point.y));
              verify(Math.hypot(point.x-nearestX, point.y-nearestY) <= radius + 0.01,
                "Badge must fit inside the rounded background, including at its ends");
            }
          }
        }
      }
    }
    function test_badges_never_move_countdowns_or_neighbouring_dials() {
      wait(20); // Let the Row and TextMetrics settle before capturing positions.
      const names = ["gptUsageDial", "claudeFiveHourDial", "claudeWeeklyDial"];
      const baseline = names.map(name => {
        const dial = findChild(block, name);
        return {dialX: dial.mapToItem(block, 0, 0).x,
          textX: countdown(name).mapToItem(block, 0, 0).x, width: dial.parent.width};
      });
      const width = block.width;
      for (const count of [0, 1, 12, null, 2, 0]) {
        for (const source of [claudeSource, codexSource])
          source.snapshot = Object.assign({}, source.snapshot,
            {resetCredits: count, resetCreditsUnavailable: count === null});
        wait(20);
        compare(block.width, width);
        for (let index = 0; index < names.length; index++) {
          const name = names[index], dial = findChild(block, name), initial = baseline[index];
          compare(dial.mapToItem(block, 0, 0).x, initial.dialX);
          compare(countdown(name).mapToItem(block, 0, 0).x, initial.textX);
          compare(dial.parent.width, initial.width);
        }
      }
    }
    function test_missing_timestamp_is_not_a_made_up_countdown() {
      const fullWidth = block.width;
      claudeSource.snapshot = {limits: [{window: "five_hour", percent: 0, resetsAt: null}]};
      compare(countdown("claudeFiveHourDial").text, "");
      verify(!countdown("claudeFiveHourDial").visible);
      compare(countdown("claudeWeeklyDial").text, "");
      tryVerify(() => block.width < fullWidth, 1000);
      compare(findChild(block, "claudeFiveHourDial").parent.width, root.theme.barSize(32),
        "An icon without a countdown reserves no text space");
      claudeSource.snapshot = {limits: [{window: "five_hour", percent: 5, resetsAt: null}]};
      compare(countdown("claudeFiveHourDial").text, "");
      claudeSource.snapshot = {limits: [{window: "five_hour", percent: 5, resetsAt: controller.now + 60000}]};
      compare(countdown("claudeFiveHourDial").text, "1 min");
      verify(countdown("claudeFiveHourDial").visible);
      codexSource.snapshot = null;
      compare(countdown("gptUsageDial").text, "");
      claudeSource.snapshot = null;
      const iconsOnlyWidth = root.theme.barSize(32) * 3 + root.theme.barSize(4) * 2
        + root.theme.barGroupHeight - root.theme.barSize(32);
      tryCompare(block, "width", iconsOnlyWidth);
      claudeSource.snapshot = {limits: [{window: "five_hour", percent: 5, resetsAt: controller.now + 60000}]};
      tryVerify(() => block.width > iconsOnlyWidth, 1000);
    }
  }
}
