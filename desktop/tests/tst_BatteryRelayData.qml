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
      if (fixture.data.snapshot !== null) receivedProcesses.push(fixture.data.snapshot.phone.updatedAt);
    });
  }
  function fakeReceiver(lifetime, exitCode = 0) {
    return ["node", "-e", 'const send=o=>process.stdout.write(JSON.stringify(o)+"\\n");'
      + 'send({event:"relay",mode:"passive",available:true,phone:{percent:73,pluggedIn:true,charging:false,updatedAt:process.pid},fitbit:null,observedAt:Date.now(),receivedAt:Date.now()});'
      + 'setTimeout(()=>process.exit(' + exitCode + '),' + lifetime + ');', "--"];
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
      fixture.data.enabled = false; fixture.data.invalidate(); fixture.data.configurationError = false;
      fixture.data.serviceUuid = "3dc63892-9fc3-4fd9-a665-3fe0b42fd876";
      fixture.data.now = Date.now(); fixture.data.restartDelay = 5000; fixture.data.staleAfterMs = 180000;
      receivedProcesses = [];
    }
    function cleanup() {
      fixture.data.enabled = false; wait(60);
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function report(phone = {}, fields = {}) {
      return Object.assign({event: "relay", mode: "passive", available: true,
        phone: Object.assign({percent: 73, pluggedIn: true, charging: false, updatedAt: fixture.data.now - 2000}, phone),
        fitbit: {percent: 42, updatedAt: fixture.data.now - 900000},
        observedAt: fixture.data.now, receivedAt: fixture.data.now}, fields);
    }
    function test_atomic_measurements_need_no_connection_event() {
      verify(fixture.data.accept(report())); verify(fixture.data.connected);
      compare(fixture.data.percent, 73);compare(fixture.data.pluggedIn, true);
      compare(fixture.data.charging, false); compare(fixture.data.fitbitPercent, 42);
    }
    function test_no_legacy_connection_or_battery_events() {
      for (const old of [{event:"connection", connected:true}, {event:"battery",device:"phone",percent:73}]) {
        fixture.data.accept(report());verify(!fixture.data.accept(old));verify(!fixture.data.connected);
      }
      verify(!fixture.data.accept(report({}, {mode:"gatt"})));
    }
    function test_zero_unknown_full_and_charging_are_independent() {
      verify(fixture.data.accept(report({percent:0,pluggedIn:false,charging:false})));compare(fixture.data.percent,0);
      verify(fixture.data.accept(report({percent:null,pluggedIn:null,charging:null})));
      verify(fixture.data.connected);compare(fixture.data.percent,null);compare(fixture.data.pluggedIn,null);
      verify(fixture.data.accept(report({percent:100,pluggedIn:true,charging:false})));
      compare(fixture.data.pluggedIn,true);compare(fixture.data.charging,false);
    }
    function test_bad_phone_or_monitor_report_clears_everything() {
      for(const bad of [{percent:101},{percent:-1},{percent:2.5},{percent:"73"},{pluggedIn:1},
          {charging:undefined},{updatedAt:0},{updatedAt:fixture.data.now+300001}]) {
        fixture.data.accept(report());verify(!fixture.data.accept(report(bad)));verify(!fixture.data.connected);
      }
      for(const bad of [{receivedAt:0},{receivedAt:Infinity},{receivedAt:fixture.data.now+6000},
          {receivedAt:fixture.data.now-fixture.data.staleAfterMs},{observedAt:0},{observedAt:fixture.data.now+6000}]) {
        fixture.data.accept(report());verify(!fixture.data.accept(report({},bad)));verify(!fixture.data.fitbitAvailable);
      }
      fixture.data.accept(report());verify(!fixture.data.acceptLine("{broken"));compare(fixture.data.snapshot,null);
    }
    function test_unchanged_percentages_do_not_expire_while_presence_is_reported() {
      const first=report();verify(fixture.data.accept(first));
      fixture.data.now+=3600000;
      verify(fixture.data.accept(Object.assign({},first,{receivedAt:fixture.data.now})));
      verify(fixture.data.connected);compare(fixture.data.updatedAt,first.phone.updatedAt);
      compare(fixture.data.snapshot.observedAt,first.observedAt);
      compare(fixture.data.fitbitUpdatedAt,first.fitbit.updatedAt);
    }
    function test_lost_presence_and_dead_helper_clear_both_sources() {
      fixture.data.accept(report());
      verify(fixture.data.accept({event:"relay",mode:"passive",available:false}));
      verify(!fixture.data.connected);verify(!fixture.data.fitbitAvailable);
      fixture.data.accept(report());fixture.data.now+=fixture.data.staleAfterMs;
      verify(!fixture.data.connected);verify(!fixture.data.fitbitAvailable);
      verify(fixture.data.accept(report()));verify(fixture.data.connected);
    }
    function test_fitbit_withdrawal_and_invalid_fitbit_do_not_break_phone() {
      for(const fitbit of [null,{percent:null,updatedAt:1},{percent:101,updatedAt:fixture.data.now},
          {percent:42,updatedAt:fixture.data.now-fixture.data.fitbitMaxAgeMs},
          {percent:42,updatedAt:fixture.data.now+300001}]) {
        verify(fixture.data.accept(report()));verify(fixture.data.fitbitAvailable);
        verify(fixture.data.accept(report({}, {fitbit})));
        verify(!fixture.data.fitbitAvailable);compare(fixture.data.percent,73);
      }
      verify(fixture.data.accept(report({}, {fitbit:{percent:0,updatedAt:fixture.data.now}})));
      compare(fixture.data.fitbitPercent,0);
    }
    function test_status_reports_do_not_refresh_cloud_source_time() {
      const first=report({}, {fitbit:{percent:42,updatedAt:fixture.data.now-fixture.data.fitbitMaxAgeMs+60000}});
      fixture.data.accept(first);verify(fixture.data.fitbitAvailable);
      fixture.data.now+=60000;
      verify(fixture.data.accept(Object.assign({},first,{receivedAt:fixture.data.now})));
      verify(!fixture.data.fitbitAvailable);verify(fixture.data.connected);
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
      fixture.data.receive(JSON.stringify(report()), oldGeneration);
      fixture.data.exited(null, oldGeneration, 78);
      verify(!fixture.data.configurationError);
      verify(!fixture.data.connected); compare(fixture.data.snapshot, null);
    }
    function test_configuration_error_stops_retrying_until_reconfigured() {
      fixture.data.command = fixture.fakeReceiver(70, 78);
      fixture.data.restartDelay = 20; fixture.data.enabled = true;
      tryVerify(() => fixture.data.configurationError, 3000);
      compare(fixture.data.transport, null); verify(!fixture.data.connected);
      const generation = fixture.data.generation;
      wait(160); compare(fixture.data.generation, generation);
      fixture.data.start(); wait(60); compare(fixture.data.generation, generation);
      // Correcting the command clears the terminal error and resumes reception.
      fixture.data.command = fixture.fakeReceiver(5000);
      tryVerify(() => fixture.data.connected, 3000);
      verify(!fixture.data.configurationError); verify(fixture.data.generation > generation);
    }
    function test_runtime_failure_still_retries() {
      fixture.data.command = fixture.fakeReceiver(70, 1);
      fixture.data.restartDelay = 20; fixture.data.enabled = true;
      tryVerify(() => new Set(receivedProcesses).size >= 2, 3000);
      verify(!fixture.data.configurationError);
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
