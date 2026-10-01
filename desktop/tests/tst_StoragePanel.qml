import QtQuick
import QtTest
import "../features/storage"

Item {
  width: 600; height: 800
  QtObject {
    id: controller
    property var snapshot: null
    property bool loading: false
    property string error: ""
    property real updatedAt: 100000
    property real now: 100000
    property int refreshes: 0
    property bool forced: false
    function refresh(force) { ++refreshes; forced = force; }
  }
  QtObject { id: state; property bool closed: false }
  StoragePanel {
    id: panel
    width: 434; height: implicitHeight
    controller: controller
    onCloseRequested: state.closed = true
  }
  TestCase {
    name: "StoragePanel"
    when: windowShown
    readonly property real gib: 1073741824
    function sample() {
      return {schemaVersion: 1, measuredAt: 100000, estimated: true,
        disk: {usedBytes: 100 * gib, availableBytes: 200 * gib, totalBytes: 300 * gib},
        categories: [{id:"docker", bytes:30*gib}, {id:"nix", bytes:10*gib},
          {id:"applications", bytes:20*gib, cacheBytes:7*gib, dataBytes:13*gib},
          {id:"personal", bytes:40*gib}, {id:"vm", bytes:0}, {id:"other", bytes:0}]};
    }
    function child(name) { return findChild(panel, name); }
    function row(id) { return child("storageRow_" + id); }
    function reading(id) { return findChild(row(id), "storageCategoryBytes").text; }
    function init() {
      controller.snapshot = sample(); controller.loading = false; controller.error = "";
      controller.refreshes = 0; controller.forced = false;
      panel.width = 434; panel.enabled = true; panel.visible = true;
      state.closed = false;
      panel.forceActiveFocus(); wait(0);
    }
    function test_readings_and_application_detail() {
      compare(child("storageTitle").text, "Stockage");
      compare(child("storageDiskUsed").text, "100,0 Gio utilisés");
      compare(child("storageDiskFree").text, "200,0 Gio libres sur 300,0 Gio");
      compare(child("storageChartTotal").text, "100,0 Gio");
      compare(child("storageChartHeading").text, "Répartition estimée");
      compare(panel.rows.length, 6);
      compare(reading("vm"), "0 Gio");
      compare(findChild(row("applications"), "storageApplicationsDetail").text,
        "Caches 7,0 Gio · Données 13,0 Gio");
      compare(findChild(row("docker"), "storageCategoryPercent").text, "30 %");
      compare(child("storageSlice_docker").sweepAngle, 108);
      verify(!child("storageSlice_vm").visible);
    }
    function test_shared_file_sum_is_not_scaled_to_disk_used() {
      const report = sample(); report.disk.usedBytes = 10 * gib;
      controller.snapshot = report;
      compare(child("storageDiskUsed").text, "10,0 Gio utilisés");
      compare(child("storageChartTotal").text, "100,0 Gio");
      compare(child("storageSlice_docker").sweepAngle, 108);
      verify(child("storageNote").text.includes("plusieurs fois"));
    }
    function test_donut_renders_the_measured_category_colors() {
      waitForRendering(panel);
      const rendered = grabImage(child("storageChart"));
      compare(rendered.width, 146); compare(rendered.height, 146);
      compare(rendered.pixel(94, 14), panel.colors.docker);
      compare(rendered.pixel(124, 110), panel.colors.nix);
      compare(rendered.pixel(73, 136), panel.colors.applications);
      compare(rendered.pixel(10, 73), panel.colors.personal);
    }
    function test_no_snapshot_and_measured_zero_remain_distinct() {
      controller.snapshot = null;
      compare(reading("vm"), "—");
      compare(child("storageChartTotal").text, "—");
      verify(!child("storageSlice_docker").visible);
      controller.loading = true;
      compare(child("storageChartCaption").text, "Mesure…");
      verify(!child("storageRefresh").enabled);
      const report = sample();
      report.categories = report.categories.map(category => Object.assign({}, category, {bytes: 0}));
      controller.snapshot = report; controller.loading = false;
      compare(child("storageChartTotal").text, "0 Gio");
      compare(reading("docker"), "0 Gio");
      compare(child("storageSlice_docker").sweepAngle, 0);
      verify(!panel.partial);
    }
    function test_partial_and_refresh_error_keep_measured_values() {
      const report = sample();
      report.categories[0].partial = true;
      report.categories[4].bytes = null;
      controller.snapshot = report;
      verify(panel.partial);
      verify(child("storageChartHeading").text.startsWith("Mesure partielle"));
      compare(reading("docker"), "≥ 30,0 Gio");
      compare(reading("vm"), "—");
      controller.error = "Échec du collecteur";
      verify(child("storageError").visible);
      verify(child("storageError").text.includes("conservée"));
      compare(reading("docker"), "≥ 30,0 Gio");
      controller.snapshot = null;
      compare(child("storageError").text, "Échec du collecteur");
    }
    function test_layout_at_small_and_large_widths() {
      for (const width of [320, 434, 500]) {
        panel.width = width; wait(20);
        verify(panel.implicitHeight > 500 && panel.implicitHeight < 620);
        for (const id of ["docker", "nix", "applications", "personal", "vm", "other"]) {
          const item = row(id), title = findChild(item, "storageCategoryLabel");
          const amount = findChild(item, "storageCategoryBytes");
          verify(title.x + title.width + 7 < amount.x + 1);
          verify(!title.truncated, "Full category label: " + id + " at " + width);
          verify(item.y + item.height <= child("storageLegend").height);
          verify(amount.x + amount.width <= item.width + 1);
        }
        const detail = findChild(row("applications"), "storageApplicationsDetail");
        verify(!detail.truncated, "Both application subtotals fit at " + width);
      }
    }
    function test_keyboard_and_click_refresh() {
      keyClick(Qt.Key_R); compare(controller.refreshes, 1); verify(controller.forced);
      mouseClick(child("storageRefresh")); compare(controller.refreshes, 2);
      panel.forceActiveFocus(); keyClick(Qt.Key_Escape); verify(state.closed);
      state.closed = false; keyClick(Qt.Key_Q); verify(state.closed);
      state.closed = false; panel.enabled = false;
      keyClick(Qt.Key_Q); verify(!state.closed);
    }
  }
}
