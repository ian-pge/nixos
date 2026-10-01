import Quickshell
import QtQuick
import QtTest

ShellRoot {
  id: fixture
  property var storage: null
  readonly property string helper: Quickshell.shellDir + "/fixtures/storage-fixture.mjs"
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/storage/StorageController.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    storage = component.createObject(fixture, {enabled: false});
  }
  TestResult { id: results }
  TestCase {
    name: "StorageController"
    when: fixture.storage !== null
    function cleanupTestCase() {
      console.log("StorageController: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function init() {
      storage.enabled = false; storage.active = false;
      wait(100);
      storage.snapshot = null; storage.lastAttempt = 0; storage.error = "";
      storage.minimumInterval = 0; storage.timeout = 5000;
      modes("ok", "ok"); storage.enabled = true;
    }
    function modes(read, scan) {
      storage.readCommand = ["node", fixture.helper, "read", read];
      storage.scanCommand = ["node", fixture.helper, "scan", scan];
    }
    function done() { tryCompare(storage, "loading", false, 6000); }
    function test_fresh_report_opens_without_a_scan_and_is_shared_on_reopen() {
      const count = storage.scanCount;
      storage.active = true; done();
      verify(storage.snapshot !== null); compare(storage.error, "");
      compare(storage.scanCount, count);
      const measured = storage.updatedAt;
      storage.active = false; storage.active = true;
      verify(!storage.loading); compare(storage.updatedAt, measured);
    }
    function test_forced_refresh_runs_once_and_closing_does_not_interrupt() {
      const count = storage.scanCount;
      storage.active = true; done();
      storage.refresh(true); storage.refresh(true);
      storage.active = false;
      done(); compare(storage.scanCount, count + 1);
      compare(storage.error, ""); verify(storage.updatedAt > 0);
    }
    function test_stale_report_is_retained_on_service_failure() {
      modes("stale", "fail");
      storage.active = true; done();
      verify(storage.snapshot !== null);
      verify(Date.now() - storage.updatedAt > 3600000);
      verify(storage.error.indexOf("Service") >= 0);
    }
    function test_success_without_a_new_report_is_not_claimed_as_refresh() {
      modes("stale", "ok");
      storage.refresh(true); done();
      verify(storage.error.indexOf("Mesure indisponible") >= 0);
      verify(Date.now() - storage.updatedAt > 3600000);
    }
    function test_invalid_report_never_becomes_zero_usage() {
      modes("invalid", "ok"); storage.refresh(true); done();
      compare(storage.snapshot, null); verify(storage.error.length > 0);
    }
    function test_missing_reader_and_service_fail_without_hanging() {
      storage.readCommand = ["/missing-storage-reader"];
      storage.scanCommand = ["/missing-storage-service"];
      storage.refresh(true); done();
      compare(storage.snapshot, null); verify(storage.error.length > 0);
    }
    function test_disabled_controller_never_starts_service() {
      const count = storage.scanCount;
      storage.enabled = false; storage.active = true; storage.refresh(true);
      wait(100); compare(storage.scanCount, count); verify(!storage.loading);
    }
    function test_disable_ignores_late_results() {
      modes("hang", "ok"); storage.active = true;
      verify(storage.loading); storage.enabled = false;
      wait(100); verify(!storage.loading); compare(storage.snapshot, null);
    }
    function test_timeout_retains_last_good_report_and_allows_retry() {
      storage.active = true; done();
      const old = storage.updatedAt;
      storage.timeout = 100; modes("ok", "hang");
      storage.refresh(true); done();
      verify(storage.error.indexOf("longue") >= 0); verify(storage.updatedAt >= old);
      wait(100); storage.timeout = 5000; modes("ok", "ok");
      storage.refresh(true); done(); compare(storage.error, "");
    }
    function test_automatic_refresh_rate_is_bounded_but_r_can_retry() {
      storage.minimumInterval = 60000;
      storage.refresh(true); done();
      const count = storage.scanCount;
      storage.refresh(); wait(100);
      compare(storage.scanCount, count); verify(!storage.loading);
      storage.refresh(true); done(); compare(storage.scanCount, count + 1);
    }
    function test_disable_and_immediate_reenable_waits_for_old_scan_exit() {
      modes("stale", "hang"); storage.active = true;
      tryCompare(storage, "phase", "scan", 3000);
      const count = storage.scanCount;
      storage.enabled = false;
      modes("ok", "ok"); storage.enabled = true;
      tryVerify(() => !storage.loading && storage.snapshot !== null
        && Date.now() - storage.updatedAt < 5000, 6000);
      compare(storage.error, ""); compare(storage.scanCount, count);
    }
  }
}
