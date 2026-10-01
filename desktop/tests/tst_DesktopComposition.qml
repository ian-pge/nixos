import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Instantiate the complete production composition only in a private nested
// Wayland session, with helper processes/agents disabled and fictional chat.
ShellRoot {
  id: fixture
  property var app: null
  property var theme: null
  property string stage: ""
  property int tooltipCaptureExit: -1
  property int tooltipPointerExit: -1
  Process {
    id: tooltipPointer
    stdout: SplitParser { onRead: line => console.log("Tooltip pointer:", line) }
    stderr: SplitParser { onRead: line => console.log("Tooltip pointer error:", line) }
    onExited: code => fixture.tooltipPointerExit = code
  }
  Process {
    id: tooltipCapture
    command: [Quickshell.env("QS_TEST_GRIM"), Quickshell.env("QS_TOOLTIP_DIAGNOSTIC")]
    onExited: code => fixture.tooltipCaptureExit = code
  }
  QtObject {
    id: noticeState
    property bool visible: false
    property string targetMonitor: ""
    property var presented: ({appName: "System", summary: "Task finished", body: "Fictional notification", image: "", appIcon: ""})
    function close() { visible = false; }
    function activate() {}
  }
  QtObject {
    id: previewAudio
    property int volume: 65
    property bool muted: false
    readonly property real volumeStep: 0.05
    readonly property bool microphoneAvailable: true
    property bool microphoneMuted: false
    readonly property var outputs: []
    readonly property var inputs: []
    readonly property var sink: null
    readonly property var microphoneSource: null
    function icon() { return "volume-1"; }
    function setVolume(delta) { volume = Math.max(0, Math.min(100, volume + Math.round(delta * 100))); }
    function toggleMicrophoneMute() { microphoneMuted = !microphoneMuted; return true; }
    function deviceLabel(node) { return node.name; }
    function selectDevice(node) {}
  }
  QtObject {
    id: usageHoverProbe
    property var claude: null
    property var codex: null
    property real now: 0
    property int refreshCalls: 0
    function refresh(force) { ++refreshCalls; }
  }
  Component.onCompleted: {
    // Reloading during QtTest execution destroys its active test runner.
    Quickshell.watchFiles = false;
    if (Quickshell.env("QS_MESSENGER_PRIVATE_DBUS") !== "1"
        || Quickshell.env("QT_QPA_PLATFORM") !== "wayland") { Qt.exit(1); return; }
    theme = Qt.createQmlObject('import QtQml; import "file://' + Quickshell.shellDir + '/../ui/Theme.js" as T; QtObject { property var library: T }', fixture).library;
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../shell.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    app = component.createObject(fixture, {servicesEnabled: false});
  }
  TestResult { id: results }
  TestCase {
    name: "DesktopComposition"
    when: fixture.app !== null
    function initTestCase() {
      const screenWidth = Number(Quickshell.env("QS_BAR_SCREEN_WIDTH") || 1600);
      verify(screenWidth >= 800);
      tryVerify(() => app.bars.length > 0 && app.bars[0].screen.width > 0);
      // A nested Wayland window can inherit its tiled parent's larger size,
      // ignoring the fixture's requested output mode. Constrain the actual
      // production layer surface to the laptop's 1600px logical screen width.
      // Negative margins also permit testing a viewport wider than the nested
      // output. QS_BAR_SCREEN_WIDTH optionally probes another display size.
      const bar = app.bars[0];
      bar.margins.right = Qt.binding(() => bar.screen.width - screenWidth + 5);
      tryCompare(bar.contentItem, "width", screenWidth - 10);
    }
    function cleanupTestCase() {
      console.log("DesktopComposition: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName, fixture.stage); }
    function visibleText(item) {
      if (!item.visible) return "";
      return (typeof item.text === "string" ? item.text : "") + " "
        + Array.from(item.children || []).map(visibleText).join(" ");
    }
    function verifyNonOverlappingSurfaces(bar, surfaces) {
      const bounds = surfaces.map(item => {
        verify(item !== null && item.visible);
        const position = item.mapToItem(bar.contentItem, 0, 0);
        return {name: item.objectName, x: position.x, y: position.y, width: item.width, height: item.height};
      });
      fixture.stage = "surface bounds: " + JSON.stringify(bounds);
      for (let i = 0; i < bounds.length; ++i) {
        const a = bounds[i];
        verify(a.x >= 0 && a.x + a.width <= bar.contentItem.width + 0.5,
          a.name + " must fit in the " + bar.contentItem.width + "px bar");
        for (let j = i + 1; j < bounds.length; ++j) {
          const b = bounds[j];
          verify(a.x + a.width <= b.x + 0.5 || b.x + b.width <= a.x + 0.5
            || a.y + a.height <= b.y + 0.5 || b.y + b.height <= a.y + 0.5,
            a.name + " overlaps " + b.name);
        }
      }
    }
    function fictionalReadings(bar) {
      const services = app.services;
      const previous = {
        cpu: services.system.cpuUsage, memory: services.system.memoryUsage,
        gpu: services.system.gpuText, disk: services.system.diskUsage,
        systemSnapshot: services.system.telemetry.system, gpuSnapshot: services.system.telemetry.gpu,
        systemUpdatedAt: services.system.telemetry.systemUpdatedAt, gpuUpdatedAt: services.system.telemetry.gpuUpdatedAt,
        battery: services.power.battery, onBattery: services.power.onBattery,
        keyboards: services.power.bluetoothDevices, brightness: services.brightness.values,
        weather: services.calendar.weather.snapshot,
        claude: services.usage.claude.snapshot, codex: services.usage.codex.snapshot
      };
      services.system.cpuUsage = 23; services.system.memoryUsage = 51;
      services.system.gpuText = "17%"; services.system.diskUsage = 42;
      services.system.telemetry.acceptSystem({cpu: 23, memory: 51});
      services.system.telemetry.acceptGpu({gpu: {poweredOn: true, usage: 17,
        memoryUsedBytes: 1073741824, memoryTotalBytes: 4294967296}});
      services.power.battery = {ready: true, isPresent: true, percentage: 0.63};
      services.power.onBattery = true;
      services.power.bluetoothDevices = [{icon: "input-keyboard", address: "00:00:00:00:00:01",
        connected: true, batteryAvailable: true, battery: 0.84}];
      services.brightness.values = {[bar.monitorName]: 80};
      const day = Qt.formatDateTime(services.calendar.today, "yyyy-MM-dd");
      services.calendar.weather.snapshot = {version: 2, updatedAt: Date.now() / 1000,
        location: {name: "Preview"}, temperatureC: 19, days: {[day]: {code: 1}}};
      const future = services.usage.now + 86400000;
      services.usage.claude.snapshot = {resetCredits: 2, limits: [
        {window: "five_hour", label: "Session en cours", percent: 20, resetsAt: future},
        {window: "seven_day", label: "Semaine · tous les modèles", percent: 34, resetsAt: future},
        {label: "Semaine · modèle", percent: 99, resetsAt: future}
      ]};
      services.usage.codex.snapshot = {resetCredits: 1, limits: [{label: "Semaine", minutes: 10080, percent: 46, resetsAt: future}]};
      previewAudio.volume = 65; previewAudio.muted = false; previewAudio.microphoneMuted = false;
      bar.services = Object.assign({}, services, {audio: previewAudio});
      return () => {
        services.system.cpuUsage = previous.cpu; services.system.memoryUsage = previous.memory;
        services.system.gpuText = previous.gpu; services.system.diskUsage = previous.disk;
        services.system.telemetry.system = previous.systemSnapshot;
        services.system.telemetry.gpu = previous.gpuSnapshot;
        services.system.telemetry.systemUpdatedAt = previous.systemUpdatedAt;
        services.system.telemetry.gpuUpdatedAt = previous.gpuUpdatedAt;
        services.power.battery = previous.battery; services.power.onBattery = previous.onBattery;
        services.power.bluetoothDevices = previous.keyboards;
        services.brightness.values = previous.brightness;
        services.calendar.weather.snapshot = previous.weather;
        services.usage.claude.snapshot = previous.claude; services.usage.codex.snapshot = previous.codex;
        bar.services = Qt.binding(() => app.services);
      };
    }
    function test_grouped_bar_preserves_readings_without_overlap() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], restore = fictionalReadings(bar);
      try {
        app.coordinator.close(app.coordinator.mode);
        wait(450);
        fixture.stage = "bar geometry: " + JSON.stringify({exclusive: bar.exclusiveZone,
          capsuleTop: bar.capsuleTopInset, capsuleY: bar.capsule.y,
          messengerTop: bar.capsule.messengerHost.barTop});
        compare(bar.exclusiveZone, 52);
        compare(bar.capsuleTopInset, 10);
        compare(bar.capsule.y, bar.capsuleTopInset);
        compare(bar.capsule.messengerHost.barTop, bar.capsuleTopInset);
        compare(bar.capsule.messengerHost.workAreaTop, bar.exclusiveZone);
        const blocks = ["calendarBlock", "systemBlock", "batteryBlock", "connectivityBlock", "levelsBlock", "usageBlock"]
          .map(name => findChild(bar.contentItem, name));
        for (const block of blocks) {
          fixture.stage = "block geometry: " + (block ? block.objectName + " " + block.width + "x" + block.height : "missing");
          verify(block !== null); verify(block.visible); compare(block.height, 42);
          compare(block.mapToItem(bar.contentItem, 0, 0).y, bar.barTopInset);
        }
        const cellGroups = [["timePill", "datePill", "weatherPill"],
          ["systemPill", "gpuPill", "vramPill", "memoryPill"], ["batteryPill", "keyboardBatteryPill"],
          ["bluetoothPill", "wifiPill", "microphonePill", "doNotDisturbPill"],
          ["volumePill", "brightnessPill"], ["gptUsageDial", "claudeFiveHourDial", "claudeWeeklyDial"]];
        for (let group = 0; group < cellGroups.length; ++group) {
          const block = blocks[group];
          for (const name of cellGroups[group]) {
            const cell = findChild(block, name);
            fixture.stage = "single-row alignment: " + name;
            verify(cell !== null && cell.visible);
            const center = cell.mapToItem(block, cell.width / 2, cell.height / 2);
            compare(center.y, block.height / 2);
          }
        }
        compare(findChild(bar.contentItem, "volumePill").accent.toString(), "#eed49f");
        compare(findChild(bar.contentItem, "brightnessPill").accent.toString(), "#eed49f");
        const expected = [[servicesText("timeText"), servicesText("dateText"), "19°"]];
        function servicesText(name) { return app.services.calendar[name]; }
        for (let i = 0; i < expected.length; ++i)
          for (const value of expected[i]) {
            fixture.stage = "reading " + value + ": " + visibleText(blocks[i]);
            verify(visibleText(blocks[i]).includes(value), "Missing visible reading: " + value);
          }
        for (const [name, value] of [["systemPill", 23], ["gpuPill", 17], ["vramPill", 25], ["memoryPill", 51],
            ["batteryPill", 63], ["keyboardBatteryPill", 84],
            ["volumePill", 65], ["brightnessPill", 80], ["storagePill", 42]]) {
          const cell = findChild(bar.contentItem, name);
          verify(cell !== null && cell.visible);
          compare(cell.value, value);
          compare(cell.fraction, value / 100);
          compare(cell.tooltipText, value + "%");
          verify(findChild(cell, "dialIcon") !== null);
          verify(!visibleText(cell).includes("%"), "The percentage stays in the tooltip");
        }
        const surfaces = blocks.concat([bar.capsule,
          findChild(bar.contentItem, "storageBlock"), findChild(bar.contentItem, "updatesPill")]);
        verifyNonOverlappingSurfaces(bar, surfaces);
        for (const [rowName, names] of [
            ["leftBarModules", ["calendarBlock", "updatesPill", "connectivityBlock", "storageBlock"]],
            ["rightBarModules", ["usageBlock", "batteryBlock", "levelsBlock", "systemBlock"]]]) {
          const row = findChild(bar.contentItem, rowName);
          const children = Array.from(row.children).filter(item => item.visible && item.width > 0);
          compare(children.map(item => item.objectName).join(","), names.join(","));
          for (let i = 1; i < children.length; ++i)
            compare(children[i].x - children[i - 1].x - children[i - 1].width, row.spacing);
        }
        app.services.system.cpuUsage = 100; app.services.system.memoryUsage = 100;
        app.services.system.gpuText = "100%"; app.services.system.diskUsage = 100;
        app.services.system.telemetry.acceptSystem({cpu: 100, memory: 100});
        app.services.system.telemetry.acceptGpu({gpu: {poweredOn: true, usage: 100}});
        for (const mode of ["workspaces", "system", "calendar"]) {
          app.coordinator.open(mode, bar.monitorName);
          wait(450);
          compare(bar.exclusiveZone, 52);
          if (mode !== "workspaces") compare(bar.capsule.width, 434);
          verifyNonOverlappingSurfaces(bar, surfaces);
        }
      } finally { app.coordinator.close(app.coordinator.mode); restore(); }
    }
    function test_system_dials_keep_unknown_distinct_from_zero() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], restore = fictionalReadings(bar);
      const telemetry = app.services.system.telemetry;
      const cpu = findChild(bar.contentItem, "systemPill"), gpu = findChild(bar.contentItem, "gpuPill");
      const vram = findChild(bar.contentItem, "vramPill");
      const memory = findChild(bar.contentItem, "memoryPill");
      try {
        app.services.system.gpuText = "--";
        compare(gpu.value, 17, "Use the numeric GPU measurement, not its old text label");
        telemetry.acceptSystem({cpu: 0, memory: 0});
        compare(vram.value, 25);
        telemetry.acceptGpu({gpu: {poweredOn: true, usage: 0, memoryUsedBytes: 0, memoryTotalBytes: 4294967296}});
        for (const dial of [cpu, gpu, vram, memory]) {
          verify(dial.known); compare(dial.value, 0); compare(dial.tooltipText, "0%");
        }
        telemetry.acceptGpu({gpu: {poweredOn: true, usage: 0, memoryUsedBytes: 0, memoryTotalBytes: 0}});
        verify(gpu.known); verify(!vram.known); compare(vram.tooltipText, "—");
        telemetry.acceptGpu({gpu: {poweredOn: true, usage: 12}});
        verify(gpu.known); verify(!vram.known);
        telemetry.acceptGpu({gpu: {poweredOn: false}});
        verify(!gpu.known); compare(gpu.value, null); verify(!vram.known);
        telemetry.systemUpdatedAt = telemetry.now - 6000;
        verify(!cpu.known); verify(!memory.known);
        compare(cpu.value, null); compare(memory.value, null);
      } finally { restore(); }
    }
    function test_dials_render_a_full_circle_and_preserve_battery_states() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], restore = fictionalReadings(bar);
      const dial = findChild(bar.contentItem, "brightnessPill");
      const renderedDial = findChild(bar.contentItem, "storagePill");
      try {
        app.coordinator.close(app.coordinator.mode);
        // The left-hand storage dial stays inside the nested output even when
        // the full preview surface extends beyond its tiled parent's width.
        app.services.system.diskUsage = 100;
        wait(450);
        fixture.stage = "full dial fraction: " + renderedDial.fraction;
        compare(renderedDial.fraction, 1);
        compare(renderedDial.displayedFraction, 1);
        waitForRendering(renderedDial);
        // QtTest.grabImage returns transparent pixels for this layer surface.
        // Capture natively, as for the full bar preview, to inspect the seam
        // and all four quadrants at 100% without substituting a different view.
        const destination = Quickshell.env("QS_BAR_SCREENSHOT");
        if (destination) {
          let captured = false, saved = false;
          verify(renderedDial.grabToImage(result => {
            saved = result.saveToFile(destination.replace(/\.png$/, "-full.png"));
            captured = true;
          }));
          tryVerify(() => captured, 3000); verify(saved);
        }
        app.services.system.diskUsage = 25;
        wait(250);
        fixture.stage = "clockwise filling starts with the upper-right quarter";
        const arc = findChild(renderedDial, "dialLevelArc");
        verify(arc !== null);
        compare(arc.startAngle, -90); compare(arc.sweepAngle, 90);
        if (destination) {
          let captured = false, saved = false;
          verify(renderedDial.grabToImage(result => {
            saved = result.saveToFile(destination.replace(/\.png$/, "-quarter.png"));
            captured = true;
          }));
          tryVerify(() => captured, 3000); verify(saved);
        }
        app.services.system.diskUsage = 0;
        app.services.brightness.values = {[bar.monitorName]: 0};
        wait(250);
        fixture.stage = "empty dial";
        verify(dial.known); compare(dial.fraction, 0);
        compare(renderedDial.displayedFraction, 0);
        app.services.brightness.values = {};
        fixture.stage = "unknown dial";
        verify(!dial.known); compare(dial.value, null);
        compare(dial.tooltipText, "—"); verify(dial.accessibleText.includes("Unavailable"));

        const laptop = findChild(bar.contentItem, "batteryPill");
        const keyboard = findChild(bar.contentItem, "keyboardBatteryPill");
        app.services.power.battery = {ready: true, isPresent: true, percentage: 0.12};
        fixture.stage = "low laptop battery, normal keyboard battery";
        compare(laptop.accent.toString(), "#ed8796");
        compare(keyboard.accent.toString(), "#f4dbd6");
        app.services.power.onBattery = false;
        fixture.stage = "charging laptop battery";
        verify(laptop.charging); compare(laptop.accent.toString(), "#a6da95");
        compare(keyboard.accent.toString(), "#f4dbd6");

        const volume = findChild(bar.contentItem, "volumePill");
        previewAudio.muted = true;
        fixture.stage = "muted volume";
        compare(volume.value, 65);
        verify(volume.muted); compare(volume.tooltipText, "65%"); verify(volume.accessibleText.includes("Muted"));
        app.services.system.diskUsage = 42;
        fixture.stage = "dial hover tooltip";
        mouseMove(renderedDial, 16, 16);
        const tooltip = findChild(renderedDial, "dialTooltip");
        tryCompare(tooltip, "opened", true, 1500);
        compare(tooltip.text, "42%");
        const tooltipShape = findChild(tooltip.background, "dialTooltipGlassShape");
        verify(tooltipShape !== null, "Tooltips outside the capsules need their own compositor geometry");
        verify(tooltipShape.visible && tooltipShape.width > 0 && tooltipShape.height > 0);
        if (Quickshell.env("QS_TEST_GLASS_PLUGIN")) verify(tooltipShape.enabled);
        if (Quickshell.env("QS_TOOLTIP_DIAGNOSTIC")) {
          const tip = findChild(renderedDial, "dialTooltip");
          const hoverPoint = renderedDial.mapToItem(bar.contentItem, 16, 16);
          fixture.tooltipPointerExit = -1;
          fixture.stage = "native pointer " + JSON.stringify(hoverPoint);
          tooltipPointer.exec(["hyprctl", "dispatch", "hl.dsp.cursor.move({x="
            + Math.round((bar.screen.x || 0) + bar.margins.left + hoverPoint.x) + ",y=" + Math.round((bar.screen.y || 0) + hoverPoint.y) + "})"]);
          tryCompare(fixture, "tooltipPointerExit", 0, 3000);
          wait(900);
          console.log("Tooltip diagnostic", JSON.stringify({visible: tip.visible, opened: tip.opened,
            width: tip.width, height: tip.height, opacity: tip.opacity, popupType: tip.popupType,
            itemVisible: tip.contentItem.visible, position: tip.contentItem.mapToItem(bar.contentItem, 0, 0)}));
          fixture.tooltipCaptureExit = -1;
          tooltipCapture.running = true;
          tryCompare(fixture, "tooltipCaptureExit", 0, 3000);
        }
        compare(bar.exclusiveZone, 52);
      } finally {
        mouseMove(bar.contentItem, bar.contentItem.width / 2, 100);
        previewAudio.muted = false;
        restore();
      }
    }
    function test_dial_blocks_have_concentric_ends_and_round_singletons() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], restore = fictionalReadings(bar);
      function verifyEnds(blockName, firstName, lastName) {
        fixture.stage = "concentric ends: " + blockName;
        const block = findChild(bar.contentItem, blockName);
        const first = findChild(block, firstName), last = findChild(block, lastName);
        verify(block !== null && first !== null && last !== null);
        const firstCenter = first.mapToItem(block, first.width / 2, first.height / 2);
        const lastCenter = last.mapToItem(block, last.width / 2, last.height / 2);
        compare(firstCenter.x, block.height / 2);
        compare(firstCenter.y, block.height / 2);
        compare(lastCenter.x, block.width - block.height / 2);
        compare(lastCenter.y, block.height / 2);
        if (first === last) compare(block.width, block.height);
      }
      try {
        wait(50);
        verifyEnds("storageBlock", "storagePill", "storagePill");
        verifyEnds("systemBlock", "systemPill", "vramPill");
        verifyEnds("connectivityBlock", "bluetoothPill", "doNotDisturbPill");
        verifyEnds("batteryBlock", "batteryPill", "keyboardBatteryPill");
        verifyEnds("levelsBlock", "volumePill", "brightnessPill");
        const keyboards = app.services.power.bluetoothDevices;
        app.services.power.bluetoothDevices = [];
        wait(50);
        verifyEnds("batteryBlock", "batteryPill", "batteryPill");
        app.services.power.battery = null;
        app.services.power.bluetoothDevices = keyboards;
        wait(50);
        verifyEnds("batteryBlock", "keyboardBatteryPill", "keyboardBatteryPill");
      } finally { restore(); }
    }
    function test_block_icons_and_inset_outlines_match_dials() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], restore = fictionalReadings(bar);
      try {
        wait(50);
        for (const [name, iconName] of [
            ["timePill", "barCellIcon"], ["datePill", "barCellIcon"], ["weatherPill", "barCellIcon"],
            ["updatesPill", "pill-icon"], ["bluetoothPill", "barCellIcon"], ["wifiPill", "barCellIcon"],
            ["microphonePill", "barCellIcon"], ["doNotDisturbPill", "barCellIcon"],
            ["storagePill", "dialIcon"], ["batteryPill", "dialIcon"], ["keyboardBatteryPill", "dialIcon"],
            ["volumePill", "dialIcon"], ["brightnessPill", "dialIcon"], ["systemPill", "dialIcon"],
            ["memoryPill", "dialIcon"], ["gpuPill", "dialIcon"], ["vramPill", "dialIcon"],
            ["gptUsageDial", "dialLogo"], ["claudeFiveHourDial", "dialLogo"], ["claudeWeeklyDial", "dialLogo"]]) {
          const icon = findChild(findChild(bar.contentItem, name), iconName);
          verify(icon !== null, name);
          compare(icon.width, fixture.theme.barIconSize, name);
          compare(icon.height, fixture.theme.barIconSize, name);
        }
        for (const [name, outlineName] of [["calendarBlock", "barBlockOutline"],
            ["updatesPill", "pill-outline"]]) {
          const block = findChild(bar.contentItem, name), outline = findChild(block, outlineName);
          verify(outline.visible);
          fuzzyCompare(outline.x, fixture.theme.barOutlineInset(), 0.001);
          fuzzyCompare(outline.y, fixture.theme.barOutlineInset(), 0.001);
          fuzzyCompare(outline.width, block.width - 2 * outline.x, 0.001);
          fuzzyCompare(outline.height, 28 * fixture.theme.barScale, 0.001);
          fuzzyCompare(outline.border.width, fixture.theme.barOutlineWidth, 0.001);
          compare(outline.radius, outline.height / 2);
        }
        const connectivity = findChild(bar.contentItem, "connectivityBlock");
        fixture.stage = "connectivity has no shared outline";
        verify(!findChild(connectivity, "barBlockOutline").visible);
        for (const name of ["bluetoothPill", "wifiPill", "microphonePill", "doNotDisturbPill"]) {
          const cell = findChild(connectivity, name), ring = findChild(cell, "barCellOutline");
          fixture.stage = "connectivity ring " + name + ": " + JSON.stringify({x: ring.x, y: ring.y,
            width: ring.width, height: ring.height, radius: ring.radius, stroke: ring.border.width,
            cellWidth: cell.width, cellHeight: cell.height});
          verify(ring.visible);
          fuzzyCompare(ring.width, 28 * fixture.theme.barScale, 0.001);
          compare(ring.height, ring.width);
          compare(ring.radius, ring.width / 2);
          fuzzyCompare(ring.x + ring.width / 2, cell.width / 2, 0.001);
          fuzzyCompare(ring.y + ring.height / 2, cell.height / 2, 0.001);
          fuzzyCompare(ring.border.width, fixture.theme.barOutlineWidth, 0.001);
        }
        for (const name of ["timePill", "datePill", "weatherPill"]) {
          const cell = findChild(bar.contentItem, name), label = findChild(cell, "barCellLabel");
          fixture.stage = "calendar label " + name + ": " + label.font.pixelSize;
          compare(label.font.pixelSize, 17);
          verify(label.font.bold);
          verify(!findChild(cell, "barCellOutline").visible);
        }
      } finally { restore(); }
    }
    function test_calendar_has_one_hover_and_click_target_including_padding() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], block = findChild(bar.contentItem, "calendarBlock");
      const cells = ["timePill", "datePill", "weatherPill"].map(name => findChild(block, name));
      try {
        app.coordinator.close(app.coordinator.mode);
        verify(block.interactive);
        for (const cell of cells) verify(!cell.interactive);
        mouseMove(block, 1, block.height / 2);
        tryCompare(block, "hovered", true);
        const highlight = findChild(block, "barBlockSelection");
        const background = findChild(block, "barBlockBackground");
        compare(highlight.x, fixture.theme.barSelectionInset());
        compare(highlight.y, fixture.theme.barSelectionInset());
        compare(highlight.width, block.width - 2 * fixture.theme.barSelectionInset());
        compare(highlight.height, block.height - 2 * fixture.theme.barSelectionInset());
        compare(highlight.radius, highlight.height / 2);
        tryCompare(highlight, "color", Qt.alpha(block.accent, fixture.theme.barSelectionOpacity));
        compare(block.accent, fixture.theme.pink);
        compare(block.accent.toString(), "#f5bde6");
        compare(background.transform.length, 0);
        for (const cell of cells) verify(!cell.hovered);
        mouseClick(block, 1, block.height / 2);
        compare(app.coordinator.mode, "calendar");
        app.coordinator.close("calendar");
        for (const cell of cells) {
          mouseMove(cell, cell.width / 2, cell.height / 2);
          verify(block.hovered); verify(!cell.hovered);
          mouseClick(cell);
          compare(app.coordinator.mode, "calendar");
          app.coordinator.close("calendar");
        }
        mouseMove(bar.contentItem, bar.contentItem.width / 2, 100);
        tryCompare(block, "hovered", false);
      } finally { app.coordinator.close(app.coordinator.mode); }
    }
    function test_connectivity_selects_individual_circles() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], block = findChild(bar.contentItem, "connectivityBlock");
      const cells = ["bluetoothPill", "wifiPill", "microphonePill", "doNotDisturbPill"].map(name => findChild(block, name));
      try {
        app.coordinator.close(app.coordinator.mode);
        verify(block.circularContent); verify(!block.interactive);
        for (const cell of cells) {
          const highlight = findChild(cell, "barCellHighlight");
          verify(cell.circular); compare(cell.width, fixture.theme.barSize(32)); compare(cell.height, fixture.theme.barSize(32));
          compare(highlight.radius, cell.height / 2);
          mouseMove(cell, 16, 16);
          tryCompare(cell, "hovered", true); verify(!block.hovered);
          for (const other of cells) if (other !== cell) verify(!other.hovered);
        }
        app.coordinator.open("wifi", bar.monitorName);
        mouseMove(bar.contentItem, bar.contentItem.width / 2, 100);
        verify(cells[1].hovered); verify(!cells[0].hovered); verify(!block.hovered);
      } finally {
        app.coordinator.close(app.coordinator.mode);
        mouseMove(bar.contentItem, bar.contentItem.width / 2, 100);
      }
    }
    function test_updates_selection_is_inset_and_does_not_move() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], pill = findChild(bar.contentItem, "updatesPill");
      const background = findChild(pill, "pill-background"), highlight = findChild(pill, "pill-selection");
      try {
        app.coordinator.close(app.coordinator.mode);
        // The preceding chat test leaves its closing animation in flight.
        // Wait for its input region to disappear before hovering the left row.
        tryCompare(bar.capsule.messengerHost, "presented", false, 1000);
        wait(450);
        fixture.stage = "updates hover";
        mouseMove(pill, pill.width / 2, pill.height / 2);
        tryCompare(pill, "hovered", true);
        fixture.stage = "updates highlight color";
        tryCompare(highlight, "color", Qt.alpha(pill.accent, fixture.theme.barSelectionOpacity));
        fixture.stage = "updates highlight geometry";
        compare(highlight.x, fixture.theme.barSelectionInset());
        compare(highlight.y, fixture.theme.barSelectionInset());
        compare(highlight.width, fixture.theme.barSize(32)); compare(highlight.height, fixture.theme.barSize(32));
        compare(background.transform.length, 0);
        compare(background.mapToItem(pill, 0, 0).y, 0);
      } finally {
        mouseMove(bar.contentItem, bar.contentItem.width / 2, 100);
      }
    }
    function test_grouped_controls_keep_independent_actions() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], restore = fictionalReadings(bar);
      const oldDnd = app.services.notifications.doNotDisturb;
      try {
        for (const [name, mode] of [["systemPill", "system"], ["gpuPill", "system"], ["vramPill", "system"], ["memoryPill", "system"],
            ["wifiPill", "wifi"], ["bluetoothPill", "bluetooth"],
            ["volumePill", "audio"], ["updatesPill", "updates"]]) {
          const cell = findChild(bar.contentItem, name);
          verify(cell !== null && cell.interactive && cell.visible);
          cell.leftClicked();
          compare(app.coordinator.mode, mode);
          compare(app.coordinator.targetMonitor, bar.monitorName);
          compare(previewAudio.microphoneMuted, false);
          compare(app.services.notifications.doNotDisturb, oldDnd);
          app.coordinator.close(mode);
        }
        const microphone = findChild(bar.contentItem, "microphonePill");
        verify(microphone !== null && microphone.interactive && microphone.visible);
        microphone.leftClicked();
        compare(previewAudio.microphoneMuted, true);
        compare(app.coordinator.mode, "workspaces");
        const notifications = findChild(bar.contentItem, "doNotDisturbPill");
        notifications.leftClicked();
        compare(app.services.notifications.doNotDisturb, !oldDnd);
        compare(previewAudio.microphoneMuted, true);
        compare(app.coordinator.mode, "workspaces");
        const brightness = findChild(bar.contentItem, "brightnessPill");
        brightness.wheelUp();
        compare(app.services.brightness.value(bar.monitorName), 85);
        compare(previewAudio.volume, 65);
        compare(app.coordinator.mode, "brightness");
        findChild(bar.contentItem, "volumePill").wheelDown();
        compare(previewAudio.volume, 60);
        compare(app.services.brightness.value(bar.monitorName), 85);
        compare(app.coordinator.mode, "volume");
      } finally {
        app.coordinator.close(app.coordinator.mode);
        app.services.notifications.doNotDisturb = oldDnd;
        app.services.brightness.reset();
        restore();
      }
    }
    function test_registry_and_real_bar_bindings() {
      wait(150);
      compare(app.coordinator.mode, "workspaces");
      verify(!app.services.system.enabled); verify(!app.services.dictation.enabled);
      verify(!app.services.auth.serviceEnabled); verify(!app.services.updates.autoCheckEnabled);
      verify(!app.services.network.active); verify(!app.services.bluetooth.active);
      verify(!app.services.usage.enabled);
      verify(app.coordinator.messenger.beeperData.demo);
      tryVerify(() => app.bars.length > 0);
      const capsule = app.bars[0].capsule;
      verify(capsule !== null, "The actual Bar must instantiate its central capsule");
      compare(capsule.services.audio, app.services.audio);
      compare(capsule.coordinator, app.coordinator);
      verify(capsule.messengerHost !== null);
      verify(capsule.width > 0); verify(capsule.width <= capsule.maximumWidth);
      verify(capsule.visible);
    }
    function test_native_picker_hides_chat_and_restores_draft() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], host = bar.capsule.messengerHost;
      const composer = findChild(host, "beeperComposer");
      const panel = findChild(host, "beeperBubble").contentItem.children.find(item => typeof item.focusNavigation === "function");
      const model = app.coordinator.messenger.beeperData;
      try {
        app.coordinator.messenger.show(bar.monitorName);
        tryCompare(host, "active", true); wait(450);
        composer.forceActiveFocus(); composer.text = "Keep the draft";
        const layer = bar.WlrLayershell.layer;
        verify(layer === WlrLayer.Top || layer === WlrLayer.Overlay);
        // These are the real signals emitted for selection, cancel and failure.
        panel.nativeDialogOpened();
        verify(!host.wantsKeyboard); verify(!host.active); verify(host.presented);
        verify(!panel.attachmentPickerReady);
        tryCompare(host, "presented", false, 1000);
        verify(panel.attachmentPickerReady);
        verify(!composer.visible); compare(bar.WlrLayershell.layer, layer);
        compare(model.draftText, "Keep the draft");
        panel.nativeDialogClosed();
        verify(host.active); verify(host.presented);
        compare(bar.WlrLayershell.layer, layer); verify(host.wantsKeyboard);
        panel.compose(); tryCompare(composer, "activeFocus", true);
        compare(model.draftText, "Keep the draft");
      } finally {
        host.nativeDialogOpen = false;
        app.coordinator.messenger.hide();
      }
    }
    function test_bar_brightness_uses_its_monitor_reading() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], brightness = app.services.brightness;
      const pill = findChild(bar.contentItem, "brightnessPill");
      verify(pill !== null);
      compare(brightness.monitors, app.coordinator.monitors);
      brightness.sample = 30;
      brightness.values = {};
      compare(pill.value, null); verify(!pill.known);
      brightness.values = {[bar.monitorName]: 80, "eDP-1": 30};
      compare(pill.value, 80); compare(pill.iconName, brightness.icon(bar.monitorName));
      brightness.sample = 45;
      compare(pill.value, 80);
      brightness.values = {[bar.monitorName]: 0};
      compare(pill.value, 0); verify(pill.known);
      brightness.reset();
    }
    function test_chat_weather_handoff_has_one_material_and_one_endpoint() {
      tryVerify(() => app.bars.length > 0);
      const bar = app.bars[0], capsule = bar.capsule, host = capsule.messengerHost;
      const bubble = findChild(host, "beeperBubble"), animation = findChild(bubble, "beeperBubbleReveal");
      const capsuleGlass = findChild(capsule, "capsuleGlassShape");
      const chatGlass = findChild(bubble, "beeperGlassShape");
      try {
        bubble.animate = false;
        app.coordinator.messenger.show(bar.monitorName);
        compare(bubble.progress, 1);
        bubble.animate = true;
        app.coordinator.open("calendar", bar.monitorName);
        animation.pause();
        verify(capsule.targetHeight > 36);
        compare(bubble.capsuleWidth, capsule.targetWidth);
        compare(bubble.capsuleHeight, capsule.targetHeight);
        compare(capsule.height, capsule.targetHeight);
        for (const progress of [1, 0.6, 0.3, 0.05, 0.002]) {
          bubble.progress = progress;
          verify(bubble.visible); verify(!capsule.drawBackground);
          verify(!capsuleGlass.enabled);
          verify(!(capsuleGlass.enabled && chatGlass.enabled));
          verify(bubble.surfaceItem.height >= capsule.targetHeight);
        }
        bubble.progress = 0; animation.stop();
        verify(!bubble.visible); verify(capsule.drawBackground);
        compare(bubble.surfaceItem.width, capsule.width);
        compare(bubble.surfaceItem.height, capsule.height);
        compare(bubble.surfaceItem.y, capsule.y);
        const settledHeight = capsule.height;
        wait(80); compare(capsule.height, settledHeight, "No old height animation may finish after the handoff");

        // Reopen from weather, then reverse mid-morph toward a different panel.
        app.coordinator.messenger.show(bar.monitorName); animation.pause();
        compare(bubble.capsuleHeight, settledHeight);
        bubble.progress = 0.45;
        const before = bubble.surfaceItem.height, y = bubble.surfaceItem.y;
        app.coordinator.open("wifi", bar.monitorName); animation.pause();
        compare(bubble.surfaceItem.height, before); compare(bubble.surfaceItem.y, y);
        compare(bubble.capsuleHeight, capsule.targetHeight);
        verify(!capsule.drawBackground);
        bubble.progress = 0; animation.stop();
        compare(bubble.surfaceItem.height, capsule.height);
      } finally {
        animation.stop(); bubble.animate = false;
        app.coordinator.messenger.hide(); app.coordinator.close(app.coordinator.mode);
        bubble.animate = true;
      }
    }
    function test_system_notifications_stay_in_bar_without_stealing_chat_focus() {
      tryVerify(() => app.bars.length > 0);
      const bar = app.bars[0], capsule = bar.capsule, host = capsule.messengerHost;
      const services = capsule.services;
      capsule.services = Object.assign({}, services, {notifications: noticeState});
      app.coordinator.services = capsule.services;
      try {
        fixture.stage = "focus chat";
        app.coordinator.messenger.show(bar.monitorName);
        tryCompare(host, "active", true);
        verify(app.services.notifications.suppressChatBanners);
        wait(30); // Let the host's explicit deferred focus request settle.
        const composer = findChild(host, "beeperComposer");
        verify(composer !== null);
        composer.forceActiveFocus();
        tryCompare(composer, "activeFocus", true);
        composer.text = "Keep this draft";
        wait(450);
        const panelWidth = host.surfaceItem.width, panelHeight = host.surfaceItem.height;
        noticeState.targetMonitor = bar.monitorName; noticeState.visible = true;
        fixture.stage = "notification enters";
        tryCompare(capsule, "targetMode", "notification");
        const popup = findChild(capsule, "barNotification");
        tryVerify(() => popup !== null && popup.enabled && popup.opacity > 0.99, 1000);
        fixture.stage = "notification geometry and focus";
        compare(findChild(host, "barNotification"), null);
        compare(capsule.y, bar.capsuleTopInset); verify(capsule.width <= capsule.maximumWidth);
        compare(host.surfaceItem.width, panelWidth); compare(host.surfaceItem.height, panelHeight);
        verify(host.active); verify(composer.activeFocus); compare(composer.text, "Keep this draft");
        compare(capsule.contentOpacity("workspaces"), 0);
        // A volume/brightness request takes the same bar slot, never the chat.
        app.coordinator.showVolume(bar.monitorName);
        fixture.stage = "volume";
        verify(!noticeState.visible); compare(capsule.targetMode, "volume"); verify(host.active);
        noticeState.visible = true;
        app.coordinator.showBrightness(bar.monitorName, false);
        fixture.stage = "brightness";
        verify(!noticeState.visible); compare(capsule.targetMode, "brightness"); verify(host.active);
        app.coordinator.close("brightness");
        wait(250); compare(capsule.contentOpacity("workspaces"), 0);
        verify(composer.activeFocus); compare(composer.text, "Keep this draft");
        app.coordinator.open("audio", bar.monitorName);
        fixture.stage = "audio replacement";
        verify(!host.active); compare(app.coordinator.mode, "audio");
        verify(!app.services.notifications.suppressChatBanners);
        app.coordinator.messenger.show(bar.monitorName);
        compare(app.coordinator.mode, "workspaces"); tryCompare(host, "active", true);
        compare(composer.text, "Keep this draft");
        app.coordinator.open("calendar", bar.monitorName);
        fixture.stage = "calendar replacement";
        verify(!host.active); compare(app.coordinator.mode, "calendar");
        app.coordinator.messenger.show(bar.monitorName);
        compare(app.coordinator.mode, "workspaces"); compare(composer.text, "Keep this draft");
      } finally {
        noticeState.visible = false;
        app.coordinator.messenger.hide();
        app.coordinator.mode = "workspaces";
        capsule.services = Qt.binding(() => app.services);
        app.coordinator.services = Qt.binding(() => app.services);
      }
    }
    function test_usage_dials_replace_the_panel_without_starting_clis_in_preview() {
      fixture.stage = "usage hover-only setup";
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], capsule = bar.capsule, usage = app.services.usage;
      const restore = fictionalReadings(bar);
      const block = findChild(bar.contentItem, "usageBlock");
      const controllerBinding = block.controller;
      try {
        verify(findChild(capsule, "usagePanel") === null);
        verify(block !== null && block.visible);
        usageHoverProbe.claude = usage.claude; usageHoverProbe.codex = usage.codex;
        usageHoverProbe.now = usage.now; usageHoverProbe.refreshCalls = 0;
        block.controller = usageHoverProbe;
        // Adding the fixture's battery block repositions this right-anchored row.
        wait(50);
        for (const [name, remaining] of [["gptUsageDial", 54],
            ["claudeFiveHourDial", 80], ["claudeWeeklyDial", 66]]) {
          const dial = findChild(block, name);
          fixture.stage = "usage reading " + name + " " + dial.value;
          verify(dial !== null && dial.visible);
          compare(dial.value, remaining); compare(dial.badgeText, "");
          compare(dial.tooltipText, remaining + "%");
          verify(dial.accessibleText.includes("Réinitialisation"));
          const logo = findChild(dial, "dialLogo");
          fixture.stage = "usage logo: " + JSON.stringify({visible: logo.visible, status: logo.status,
            y: logo.y, height: logo.height, dialHeight: dial.height, source: logo.source});
          verify(logo.visible); tryCompare(logo, "status", Image.Ready);
          compare(logo.y + logo.height / 2, dial.height / 2);
          compare(logo.width, fixture.theme.barIconSize);
          const counter = findChild(dial, "resetCreditsBadge");
          verify(counter !== null);
          compare(counter.visible, name !== "claudeFiveHourDial");
          compare(findChild(counter, "resetCreditsCount").text, name === "gptUsageDial" ? "1" : "2");
          fixture.stage = "usage pointer " + name;
          verify(!dial.interactive);
          compare(findChild(dial, "dialPointer").cursorShape, Qt.ArrowCursor);
          mouseMove(dial, 16, 16);
          fixture.stage = "usage hover " + name;
          tryCompare(findChild(dial, "dialTooltip"), "opened", true, 1500);
          fixture.stage = "usage ignore click " + name;
          mouseClick(dial); dial.leftClicked();
          fixture.stage = "usage no action " + name;
          compare(usageHoverProbe.refreshCalls, 0);
          compare(app.coordinator.mode, "workspaces");
        }
        app.coordinator.open("usage", bar.monitorName);
        compare(app.coordinator.mode, "workspaces");
        verify(!usage.enabled); verify(!usage.active); verify(!usage.loading);
        compare(usage.claude.run, 0); compare(usage.codex.run, 0);
        const claudeDial = findChild(block, "claudeWeeklyDial");
        const count = findChild(claudeDial, "resetCreditsCount");
        const counter = findChild(claudeDial, "resetCreditsBadge");
        usage.claude.snapshot = Object.assign({}, usage.claude.snapshot, {resetCredits: 0});
        verify(!counter.visible); compare(count.text, "");
        usage.claude.snapshot = Object.assign({}, usage.claude.snapshot, {resetCredits: null});
        verify(!counter.visible); compare(count.text, "");
        usage.claude.snapshot = Object.assign({}, usage.claude.snapshot, {resetCredits: 1});
        verify(counter.visible); compare(count.text, "1");
      } finally {
        block.controller = Qt.binding(() => controllerBinding);
        mouseMove(bar.contentItem, bar.contentItem.width / 2, 100);
        restore();
      }
    }
    function test_storage_opens_from_the_pill_without_starting_a_scan_in_preview() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], capsule = bar.capsule, storage = app.services.storage;
      const pill = findChild(bar.contentItem, "storagePill");
      const panel = findChild(capsule, "storagePanel");
      verify(pill !== null); verify(panel !== null); verify(pill.interactive);
      try {
        pill.leftClicked();
        tryCompare(capsule, "targetMode", "storage");
        verify(capsule.keyboardSelectorActive);
        compare(capsule.targetWidth, capsule.maximumWidth);
        compare(capsule.targetHeight, panel.implicitHeight);
        tryCompare(capsule, "height", panel.implicitHeight, 1000);
        tryVerify(() => panel.opacity > 0.99, 1000);
        verify(storage.active); verify(!storage.enabled); verify(!storage.loading);
        compare(storage.scanCount, 0);
        pill.leftClicked();
        compare(app.coordinator.mode, "workspaces"); verify(!storage.active);
      } finally { app.coordinator.close("storage"); }
    }
    function test_scrolling_history_does_not_resize_the_top_bar_or_panel() {
      tryVerify(() => app.bars.length > 0);
      const bar = app.bars[0], capsule = bar.capsule, host = capsule.messengerHost;
      const model = app.coordinator.messenger.beeperData;
      app.coordinator.messenger.show(bar.monitorName);
      tryCompare(host, "active", true); wait(450);
      const width = capsule.width, height = capsule.height;
      const panelWidth = host.surfaceItem.width, panelHeight = host.surfaceItem.height;
      const list = findChild(host, "beeperMessages");
      try {
        for (let i = 0; i < 6; ++i) {
          mouseWheel(list, list.width / 2, list.height / 2, 0, i < 3 ? 120 : -120, Qt.NoButton);
          wait(40);
          compare(capsule.width, width); compare(capsule.height, height);
          compare(host.surfaceItem.width, panelWidth); compare(host.surfaceItem.height, panelHeight);
        }
      } finally { app.coordinator.messenger.hide(); }
    }
    function test_z_optional_grouped_bar_screenshot() {
      const destination = Quickshell.env("QS_BAR_SCREENSHOT");
      if (!destination) return;
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
      const bar = app.bars[0], restore = fictionalReadings(bar);
      let capture = null;
      let children = [];
      try {
        app.coordinator.messenger.hide();
        app.coordinator.close(app.coordinator.mode);
        wait(500);
        // Quickshell's native contentItem has no QML engine for grabToImage.
        // A temporary wrapper preserves the production layout while providing
        // a QML-owned capture root; restore every child before disposing it.
        children = Array.from(bar.contentItem.children);
        capture = Qt.createQmlObject("import QtQuick; Item { width: parent.width; height: 60 }", bar.contentItem);
        for (const child of children) child.parent = capture;
        wait(50);
        let finished = false, saved = false;
        verify(capture.grabToImage(result => {
          saved = result.saveToFile(destination);
          finished = true;
        }));
        tryVerify(() => finished, 3000);
        verify(saved, "Could not save grouped bar preview: " + destination);
        console.log("Grouped bar preview:", destination);
      } finally {
        for (const child of children) child.parent = bar.contentItem;
        if (capture) capture.destroy();
        restore();
      }
    }
  }
}
