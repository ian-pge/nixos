import QtQuick
import QtTest
import Quickshell

// Fake NDJSON only; no Bluetooth, pairing, USB or real receiver process.
ShellRoot {
  id: fixture
  property var data: null
  property var receivedProcesses: []
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/power/BatteryRelayData.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    data = component.createObject(fixture, {enabled: false});
    fixture.data.snapshotChanged.connect(() => {
      if (fixture.data.snapshot !== null) receivedProcesses.push(fixture.data.snapshot.updatedAt);
    });
  }
  function fakeReceiver(lifetime) {
    return ["node", "-e", 'const send=o=>process.stdout.write(JSON.stringify(o)+"\\n");'
      + 'send({event:"connection",connected:true});'
      + 'send({event:"battery",device:"phone",percent:73,pluggedIn:true,charging:false,updatedAt:process.pid,receivedAt:Date.now()});'
      + 'setTimeout(()=>process.exit(0),' + lifetime + ');', "--"];
  }
  TestResult { id: results }
  TestCase {
    name: "BatteryRelayData"
    when: fixture.data !== null
    function cleanupTestCase() {
      fixture.data.enabled = false;
      console.log("BatteryRelayData: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function init() {
      fixture.data.enabled = false; fixture.data.invalidate();
      fixture.data.serviceUuid = "3dc63892-9fc3-4fd9-a665-3fe0b42fd876";
      fixture.data.now = Date.now(); fixture.data.restartDelay = 5000; fixture.data.staleAfterMs = 180000;
      receivedProcesses = [];
    }
    function cleanup() {
      fixture.data.enabled = false; wait(60);
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function report(overrides = {}) {
      return Object.assign({event: "battery", device: "phone", percent: 73,
        pluggedIn: true, charging: false, updatedAt: fixture.data.now + 2000, receivedAt: fixture.data.now}, overrides);
    }
    function connect() { verify(fixture.data.accept({event: "connection", connected: true})); }
    function test_connection_without_measurement_is_not_a_battery() {
      connect(); verify(!fixture.data.connected); compare(fixture.data.percent, null);
      verify(fixture.data.accept(report())); verify(fixture.data.connected); compare(fixture.data.percent, 73);
      compare(fixture.data.pluggedIn, true); compare(fixture.data.charging, false);
    }
    function test_zero_unknown_and_active_charge_are_independent() {
      connect(); verify(fixture.data.accept(report({percent: 0, pluggedIn: false, charging: false})));
      compare(fixture.data.percent, 0); compare(fixture.data.pluggedIn, false);
      verify(fixture.data.accept(report({percent: null, pluggedIn: null, charging: null})));
      verify(fixture.data.connected); compare(fixture.data.percent, null); compare(fixture.data.pluggedIn, null);
      verify(fixture.data.accept(report({percent: 100, pluggedIn: true, charging: false})));
      compare(fixture.data.charging, false); compare(fixture.data.pluggedIn, true);
    }
    function test_bad_samples_and_malformed_json_clear_previous_values() {
      for (const bad of [{percent: 101}, {percent: -1}, {percent: 2.5}, {percent: "73"},
          {pluggedIn: 1}, {charging: undefined}, {updatedAt: 0}, {receivedAt: Infinity},
          {receivedAt: fixture.data.now + 6000}, {receivedAt: fixture.data.now - fixture.data.staleAfterMs}]) {
        connect(); verify(fixture.data.accept(report())); verify(!fixture.data.accept(report(bad)));
        verify(!fixture.data.connected); compare(fixture.data.percent, null); compare(fixture.data.pluggedIn, null);
      }
      connect(); fixture.data.accept(report()); verify(!fixture.data.acceptLine("{broken")); compare(fixture.data.snapshot, null);
    }
    function test_disconnect_requires_a_new_connection_report() {
      connect(); fixture.data.accept(report()); fixture.data.accept({event: "connection", connected: false});
      verify(!fixture.data.connected); compare(fixture.data.snapshot, null);
      verify(!fixture.data.accept(report())); verify(!fixture.data.connected);
      connect(); verify(fixture.data.accept(report({percent: 74}))); compare(fixture.data.percent, 74);
    }
    function test_stale_after_suspend_clears_and_fresh_heartbeat_recovers() {
      connect(); fixture.data.accept(report());
      fixture.data.now += fixture.data.staleAfterMs;
      verify(!fixture.data.connected); compare(fixture.data.percent, null); compare(fixture.data.pluggedIn, null);
      verify(fixture.data.accept(report({percent: 74}))); verify(fixture.data.connected);
      compare(fixture.data.percent, 74);
    }
    function test_other_devices_never_refresh_the_phone() {
      connect(); fixture.data.accept(report()); const original = fixture.data.snapshot;
      verify(fixture.data.accept(report({device: "fitbit", percent: 90, pluggedIn: null, charging: null})));
      compare(fixture.data.snapshot, original); compare(fixture.data.percent, 73);
      verify(!fixture.data.accept(report({device: "future-device"})));
      compare(fixture.data.snapshot, original);
    }
    function fitbitReport(overrides = {}) {
      return report(Object.assign({device: "fitbit", percent: 42, pluggedIn: null, charging: null,
        updatedAt: fixture.data.now - 15 * 60000}, overrides));
    }
    function test_fitbit_needs_phone_and_retains_cloud_sync_time() {
      connect(); verify(!fixture.data.accept(fitbitReport())); verify(!fixture.data.fitbitAvailable);
      fixture.data.accept(report()); verify(fixture.data.accept(fitbitReport()));
      verify(fixture.data.fitbitAvailable); compare(fixture.data.fitbitPercent, 42);
      compare(fixture.data.fitbitUpdatedAt, fixture.data.now - 15 * 60000);
      verify(fixture.data.accept(fitbitReport({percent: 0}))); compare(fixture.data.fitbitPercent, 0);
    }
    function test_fitbit_heartbeats_cannot_make_old_cloud_data_fresh() {
      connect(); fixture.data.accept(report());
      const sourceTime = fixture.data.now - fixture.data.fitbitMaxAgeMs + 60000;
      verify(fixture.data.accept(fitbitReport({updatedAt: sourceTime}))); verify(fixture.data.fitbitAvailable);
      fixture.data.now += 60000;
      fixture.data.accept(report());
      verify(!fixture.data.accept(fitbitReport({updatedAt: sourceTime})));
      verify(!fixture.data.fitbitAvailable); verify(fixture.data.connected);
    }
    function test_fitbit_cannot_extend_phone_liveness_and_clear_is_explicit() {
      connect(); fixture.data.accept(report()); fixture.data.accept(fitbitReport());
      fixture.data.now += fixture.data.staleAfterMs - 1;
      verify(fixture.data.accept(fitbitReport()));
      fixture.data.now += 1;
      verify(!fixture.data.connected); verify(!fixture.data.fitbitAvailable);
      fixture.data.accept(report()); fixture.data.accept(fitbitReport());
      verify(fixture.data.accept(fitbitReport({percent: null}))); verify(!fixture.data.fitbitAvailable);
      verify(fixture.data.connected);
      fixture.data.accept(fitbitReport()); fixture.data.invalidate();
      compare(fixture.data.fitbitSnapshot, null); verify(!fixture.data.fitbitAvailable);
    }
    function test_bad_fitbit_never_invents_charge_or_breaks_phone() {
      for (const bad of [{percent: 101}, {percent: -1}, {percent: 2.5}, {percent: "42"},
          {pluggedIn: true}, {charging: false}, {updatedAt: 0}, {updatedAt: fixture.data.now + 300001},
          {updatedAt: fixture.data.now - fixture.data.fitbitMaxAgeMs}, {receivedAt: fixture.data.now + 6000}]) {
        connect(); fixture.data.accept(report()); fixture.data.accept(fitbitReport());
        verify(!fixture.data.accept(fitbitReport(bad))); verify(!fixture.data.fitbitAvailable);
        compare(fixture.data.percent, 73); verify(fixture.data.connected);
      }
    }
    function test_receiver_eof_clears_values_without_disconnect_packet() {
      fixture.data.command = fixture.fakeReceiver(100); fixture.data.enabled = true;
      tryVerify(() => receivedProcesses.length > 0, 3000);
      tryVerify(() => fixture.data.transport === null, 3000);
      verify(!fixture.data.connected); compare(fixture.data.percent, null); compare(fixture.data.pluggedIn, null);
    }
    function test_receiver_restarts_and_stops_when_disabled() {
      fixture.data.command = fixture.fakeReceiver(70); fixture.data.restartDelay = 20; fixture.data.enabled = true;
      tryVerify(() => new Set(receivedProcesses).size >= 2, 3000);
      fixture.data.enabled = false; wait(100);
      const count = receivedProcesses.length;
      wait(160); compare(receivedProcesses.length, count); compare(fixture.data.transport, null);
      verify(!fixture.data.connected);
    }
    function test_old_process_cannot_repopulate_after_service_change() {
      fixture.data.command = ["node", "-e", "setTimeout(()=>{},5000);", "--"];
      fixture.data.enabled = true; tryVerify(() => fixture.data.transport !== null);
      const oldGeneration = fixture.data.generation;
      fixture.data.serviceUuid = "6e20809a-d042-49df-8d1c-e2d777280f29";
      fixture.data.receive(JSON.stringify({event: "connection", connected: true}), oldGeneration);
      fixture.data.receive(JSON.stringify(report()), oldGeneration);
      verify(!fixture.data.connected); compare(fixture.data.snapshot, null);
    }
    function test_missing_or_invalid_configuration_never_starts_a_process() {
      fixture.data.command = fixture.fakeReceiver(50);
      for (const id of ["", "not-a-uuid", "00000000-0000-0000-0000-000000000000"]) {
        fixture.data.enabled = false; fixture.data.serviceUuid = id; fixture.data.enabled = true;
        wait(40); verify(!fixture.data.configured); compare(fixture.data.transport, null);
      }
      compare(receivedProcesses.length, 0);
    }
  }
}
