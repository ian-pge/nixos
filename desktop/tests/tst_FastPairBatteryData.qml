import QtQuick
import QtTest
import Quickshell

// Fictional NDJSON, no key file read and no Bluetooth.
ShellRoot {
  id: fixture
  property var data: null
  Component.onCompleted: {
    const c = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/power/FastPairBatteryData.qml");
    if (c.status !== Component.Ready) { console.error(c.errorString()); Qt.exit(1); return; }
    data = c.createObject(fixture, {enabled:false});
  }
  TestResult { id: results }
  TestCase {
    name: "FastPairBatteryData"
    when: fixture.data !== null
    function init() {
      fixture.data.enabled = false; fixture.data.invalidate(); fixture.data.configurationError = false;
      fixture.data.now = Date.now(); fixture.data.keyFile = "/fictional/private/key";
      fixture.data.restartDelay = 5000;
    }
    function cleanup() { fixture.data.enabled = false; wait(30); }
    function cleanupTestCase() {
      console.log("FastPairBatteryData: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function report(overrides = {}) {
      return Object.assign({event:"earbuds", available:true,
        case:{percent:85,charging:false},left:{percent:100,charging:true},right:{percent:19,charging:false},
        observedAt:fixture.data.now,receivedAt:fixture.data.now},overrides);
    }
    function test_reading_needs_no_phone_connection() {
      verify(fixture.data.accept(report())); verify(fixture.data.available);
      compare(fixture.data.snapshot.case.percent,85);
      verify(fixture.data.accept(report({case:{percent:0,charging:false}})));
      compare(fixture.data.snapshot.case.percent,0);
    }
    function test_missing_case_never_uses_bud_level() {
      verify(fixture.data.accept(report({case:{percent:null,charging:null}})));
      verify(fixture.data.available); compare(fixture.data.snapshot.case.percent,null);
    }
    function test_bad_or_stale_readings_are_withdrawn() {
      for (const bad of [{case:{percent:101,charging:false}},{left:{percent:"19",charging:false}},
          {right:{percent:19,charging:1}},{case:[]},{available:"yes"},{observedAt:0},
          {receivedAt:fixture.data.now+6000},{observedAt:fixture.data.now-180000},
          {receivedAt:fixture.data.now-180000}]) {
        verify(fixture.data.accept(report()));
        verify(!fixture.data.accept(report(bad))); verify(!fixture.data.available);
      }
      verify(!fixture.data.acceptLine("{broken")); verify(!fixture.data.available);
    }
    function test_unchanged_percentages_stay_visible_with_new_observations() {
      verify(fixture.data.accept(report()));
      fixture.data.now += 170000;
      verify(fixture.data.accept(report()));
      fixture.data.now += 170000;
      verify(fixture.data.available); compare(fixture.data.snapshot.case.percent,85);
      fixture.data.now += 10000;
      verify(!fixture.data.available);
    }
    function test_explicit_withdrawal_and_suspend_clear_readings() {
      const unknown = {percent:null,charging:null};
      verify(fixture.data.accept(report()));
      verify(fixture.data.accept(report({available:false,case:unknown,left:unknown,right:unknown,observedAt:null})));
      verify(!fixture.data.available);
      verify(fixture.data.accept(report())); fixture.data.now += 3600000;
      verify(!fixture.data.available);
    }
    function test_old_process_generation_is_ignored() {
      fixture.data.command = ["node","-e","setTimeout(()=>{},5000)","--"];
      fixture.data.enabled = true; tryVerify(() => fixture.data.transport !== null);
      const generation = fixture.data.generation;
      fixture.data.keyFile = "/fictional/another/key";
      fixture.data.receive(JSON.stringify(report()),generation);
      verify(!fixture.data.available);
    }
    function test_configuration_error_stops_retrying_until_reconfigured() {
      fixture.data.command = ["node","-e","process.exit(78)","--"];
      fixture.data.restartDelay = 10; fixture.data.enabled = true;
      tryVerify(() => fixture.data.configurationError,3000);
      compare(fixture.data.transport,null);
      const generation = fixture.data.generation;
      wait(100); compare(fixture.data.generation,generation);
    }
    function test_invalid_key_path_never_starts_receiver() {
      fixture.data.command = ["node","-e","setTimeout(()=>{},5000)","--"];
      for (const path of ["","relative/key","/nix/store/secret"]) {
        fixture.data.enabled = false; fixture.data.keyFile = path; fixture.data.enabled = true;
        wait(30); verify(!fixture.data.configured); compare(fixture.data.transport,null);
      }
    }
    function test_eof_clears_data_and_process_can_restart() {
      fixture.data.command = ["node","-e",
        'process.stdout.write(JSON.stringify({event:"earbuds",available:true,case:{percent:85,charging:false},left:{percent:100,charging:true},right:{percent:100,charging:true},observedAt:Date.now(),receivedAt:Date.now()})+"\\n");setTimeout(()=>process.exit(0),200)',"--"];
      fixture.data.enabled = true;
      tryVerify(() => fixture.data.available,3000);
      tryVerify(() => fixture.data.transport === null,3000);
      verify(!fixture.data.available);
    }
  }
}
