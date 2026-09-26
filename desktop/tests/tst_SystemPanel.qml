import QtQuick
import QtTest

import "../ui/Theme.js" as Theme
import "../features/notifications"
import "../features/system"

Item {
  width: 500; height: 800
  QtObject {
    id: telemetryModel
    property bool systemFresh: true
    property bool gpuFresh: true
    property var system: null
    property var gpu: null
    property real now: 100000
    property bool processTopFresh: true
    property bool gpuTopFresh: true
    property var processTop: null
    property var gpuTop: null
  }
  QtObject {
    id: state
    property bool closed: false
  }
  SystemPanel { id: panel; width: 434; height: implicitHeight; telemetry: telemetryModel; onCloseRequested: state.closed = true }
  NotificationInputGuard {
    id: guard
    anchors.fill: parent; z: 2
    active: false; captureInput: true
    onDismissed: active = false
  }

  TestCase {
    name: "SystemPanel"
    when: windowShown
    function init() {
      guard.active = false;
      telemetryModel.system = {cpu: 12, memory: 25, cpuName: "Test CPU", cpuTemperatureC: 55,
        cpuFrequencyMHz: 2800, memoryUsedBytes: 17179869184, memoryTotalBytes: 68719476736,
        swapUsedBytes: 0, swapTotalBytes: 0};
      telemetryModel.gpu = {name: "Test GPU", poweredOn: true, usage: 0, temperatureC: 42,
        memoryUsedBytes: 2147483648, memoryTotalBytes: 8589934592};
      telemetryModel.systemFresh = true; telemetryModel.gpuFresh = true;
      const rows = [];
      for (let pid=1; pid<=5; pid++) rows.push({pid, name:"Processus " + pid,
        usage: pid === 1 ? 150 : 10, memoryBytes: 1073741824});
      telemetryModel.processTop = {cpu:rows, memory:rows};
      telemetryModel.gpuTop = {sort:"gpu",rows:rows.map(row => Object.assign({}, row, {usage:10}))};
      telemetryModel.processTopFresh = true; telemetryModel.gpuTopFresh = true;
      panel.width = 434; panel.visible = true; panel.enabled = true;
      state.closed = false;
      panel.forceActiveFocus();
      wait(0);
    }
    function child(name) { return findChild(panel, name); }
    function test_contents_order_and_palette() {
      compare(child("systemTitle").text, "Système");
      compare(child("cpuHeading").value, "12 %");
      compare(child("gpuHeading").value, "0 %");
      compare(child("memoryDetails").text, "16,0 / 64,0 Gio");
      verify(child("cpuDetails").text.includes("55 °C"));
      verify(child("cpuDetails").text.includes("2,80 GHz"));
      verify(child("gpuDetails").text.includes("2,0 / 8,0 Gio"));
      verify(child("cpuSection").y < child("memorySection").y);
      verify(child("memorySection").y < child("gpuSection").y);
      for (const name of ["cpuProcesses", "memoryProcesses", "gpuProcesses"]) {
        compare(child(name).accent, Theme.sideSystem);
        compare(child(name).entries.length, 5);
      }
      const first = findChild(child("cpuProcesses"), "processRow0");
      compare(findChild(first, "processName").text, "Processus 1");
      compare(findChild(first, "processReading").text, "150 %");
      compare(child("cpuGraph"), null);
      compare(child("memoryTrack"), null);
    }
    function test_compact_height_and_swap() {
      const normalHeight = panel.implicitHeight;
      verify(!child("swapDetails").visible);
      telemetryModel.system = Object.assign({}, telemetryModel.system, {swapUsedBytes: 536870912, swapTotalBytes: 8589934592});
      verify(child("swapDetails").visible);
      compare(child("swapDetails").text, "Swap  0,5 / 8,0 Gio");
      compare(panel.implicitHeight, normalHeight + 24);
      verify(panel.implicitHeight < 800);
      telemetryModel.system = Object.assign({}, telemetryModel.system, {swapUsedBytes: 0});
      compare(panel.implicitHeight, normalHeight);
      compare(panel.implicitHeight, child("systemFooter").y + 28);
    }
    function test_missing_stale_and_sleeping_gpu() {
      telemetryModel.gpu = Object.assign({}, telemetryModel.gpu, {poweredOn: false, usage: null, temperatureC: null});
      compare(child("gpuHeading").value, "Veille");
      telemetryModel.systemFresh = false; telemetryModel.gpuFresh = false;
      compare(child("cpuHeading").value, "—");
      compare(child("memoryDetails").text, "—");
      compare(child("gpuHeading").value, "—");
      verify(child("cpuDetails").text.includes("Temp. —"));
      telemetryModel.system = null; telemetryModel.gpu = null;
      compare(child("cpuModel").text, "Processeur");
      compare(child("gpuModel").text, "Carte graphique");
    }
    function test_long_models_and_width_changes_do_not_grow_height() {
      const height = panel.implicitHeight;
      telemetryModel.system = Object.assign({}, telemetryModel.system, {cpuName: "A very long CPU name ".repeat(12)});
      for (const width of [320, 434, 500]) {
        panel.width = width;
        compare(panel.implicitHeight, height);
        compare(child("cpuModel").elide, Text.ElideRight);
        verify(child("cpuSection").x + child("cpuSection").width <= panel.width);
        verify(child("gpuSection").x + child("gpuSection").width <= panel.width);
      }
      panel.visible = false;
      telemetryModel.system = Object.assign({}, telemetryModel.system, {swapUsedBytes: 1, swapTotalBytes: 100});
      compare(panel.implicitHeight, height + 24);
    }
    function test_empty_lists_shrink_height_and_vram_fallback_is_labeled() {
      const fullHeight = panel.implicitHeight;
      telemetryModel.processTop = {cpu:[], memory:[]};
      telemetryModel.gpuTop = {sort:"vram", rows:[]};
      verify(panel.implicitHeight < fullHeight);
      verify(child("gpuProcesses").heading.startsWith("Top VRAM"));
      compare(child("gpuProcesses").metric, "vram");
      compare(findChild(child("cpuProcesses"), "processEmpty").text, "Aucun processus");
      telemetryModel.processTopFresh = false;
      compare(child("cpuProcesses").rows, null);
      compare(findChild(child("cpuProcesses"), "processEmpty").text, "Mesure en cours…");
      telemetryModel.gpuTopFresh = false;
      telemetryModel.gpu = Object.assign({}, telemetryModel.gpu, {poweredOn:false});
      compare(findChild(child("gpuProcesses"), "processEmpty").text, "Carte en veille");
    }
    function test_escape_closes_only_the_panel() {
      keyClick(Qt.Key_Escape);
      verify(state.closed);
      state.closed = false; panel.enabled = false;
      keyClick(Qt.Key_Escape);
      verify(!state.closed);
    }
    function test_focus_returns_after_a_notification_covers_the_panel() {
      guard.active = true;
      tryCompare(guard, "activeFocus", true);
      panel.visible = false;
      keyClick(Qt.Key_Escape);
      verify(!guard.active);
      verify(!state.closed);
      panel.visible = true;
      tryCompare(panel, "activeFocus", true);
      keyClick(Qt.Key_Escape);
      verify(state.closed);
    }
  }
}
