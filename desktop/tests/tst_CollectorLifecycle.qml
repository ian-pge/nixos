import QtQuick
import QtTest
import Quickshell

// Only short-lived, injected Node streams run. No real telemetry or microphone.
ShellRoot {
  id: fixture
  property var system: null
  property var dictation: null
  property int systemSamples: 0
  property int gpuSamples: 0
  property int recordings: 0
  property int audioConnections: 0
  property var systemProcesses: []
  property var gpuReports: []
  function collector(gpu, oneShot) {
    const report = gpu
      ? '{text:String(generation)' + (oneShot ? '+":"+process.pid' : '') + ',gpu:{poweredOn:false},top:{generation,rows:[],state:"sleeping"}}'
      : '{cpu:12,memory:25,disk:50,brightness:' + (oneShot ? 'process.pid' : '70') + ',top:{generation,cpu:[],memory:[]}}';
    return ["node", "-e", 'let buffer="";process.stdin.setEncoding("utf8");process.stdin.on("data",chunk=>{buffer+=chunk;let pos;while((pos=buffer.indexOf("\\n"))>=0){const generation=Number(buffer.slice(0,pos));buffer=buffer.slice(pos+1);process.stdout.write(JSON.stringify(' + report + ')+"\\n");' + (oneShot ? 'setTimeout(()=>process.exit(0),40);' : '') + '}});'];
  }
  function stream(line) {
    return ["node", "-e", 'process.stdout.write(' + JSON.stringify(line + "\n") + ');setTimeout(()=>process.exit(0),80);'];
  }
  function create(name, properties) {
    const c = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/" + name + ".qml");
    if (c.status !== Component.Ready) { console.error(c.errorString()); Qt.exit(1); return null; }
    return c.createObject(fixture, properties);
  }
  Component.onCompleted: {
    system = create("system/SystemController", {enabled: false, statsRestartDelay: 30, gpuRestartDelay: 30});
    dictation = create("dictation/DictationController", {enabled: false, statusRestartDelay: 30, audioRestartDelay: 30});
    system.brightnessSample.connect(value => { systemSamples++; systemProcesses.push(value); });
    system.gpuTextChanged.connect(() => {
      if (system.gpuText === "--") return;
      const parts = system.gpuText.split(":");
      gpuReports.push({generation: Number(parts[0]), pid: Number(parts[1])});
    });
    system.telemetry.gpuUpdatedAtChanged.connect(() => { if (system.telemetry.gpuUpdatedAt > 0) gpuSamples++; });
    dictation.recordingChanged.connect(() => { if (dictation.recording) recordings++; });
    dictation.audioConnectedChanged.connect(() => { if (dictation.audioConnected) audioConnections++; });
  }
  TestResult { id: results }
  TestCase {
    name: "CollectorLifecycle"
    when: fixture.dictation !== null
    function cleanupTestCase() {
      console.log("CollectorLifecycle: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() {
      system.enabled = false; dictation.enabled = false;
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      wait(100);
    }
    function init() {
      system.enabled = false; dictation.enabled = false; system.topRequested = false;
      systemSamples = 0; gpuSamples = 0; recordings = 0; audioConnections = 0;
      systemProcesses = []; gpuReports = [];
    }
    function test_collectors_receive_subscriptions_after_each_restart() {
      system.statsCommand = fixture.collector(false, true);
      system.gpuCommand = fixture.collector(true, true);
      system.topRequested = true;
      const generation = system.telemetry.topRequestId;
      system.enabled = true;
      // Observe at least two distinct child processes, not a transient value
      // that is legitimately cleared as soon as a one-shot collector exits.
      tryVerify(() => new Set(systemProcesses).size >= 2
        && new Set(gpuReports.map(report => report.pid)).size >= 2, 4000);
      verify(gpuReports.every(report => report.generation === generation));
      system.enabled = false; wait(100);
      verify(!system.telemetry.systemFresh); verify(!system.telemetry.gpuFresh);
      const samples = systemSamples, gpuReportCount = gpuSamples;
      wait(160); compare(systemSamples, samples); compare(gpuSamples, gpuReportCount);
    }
    function test_collectors_follow_open_close_reopen_generation() {
      system.statsCommand = fixture.collector(false, false);
      system.gpuCommand = fixture.collector(true, false);
      system.enabled = true;
      tryCompare(system, "gpuText", "0", 2000);
      verify(!system.telemetry.processTopFresh);
      system.topRequested = true;
      tryVerify(() => system.telemetry.processTopFresh, 2000);
      tryCompare(system, "gpuText", String(system.telemetry.topRequestId), 2000);
      const generation = system.telemetry.topRequestId;
      system.topRequested = false; verify(!system.telemetry.processTopFresh);
      tryCompare(system, "gpuText", "0", 2000);
      system.topRequested = true;
      verify(system.telemetry.topRequestId > generation);
      tryCompare(system, "gpuText", String(system.telemetry.topRequestId), 2000);
      tryVerify(() => system.telemetry.processTopFresh, 2000);
    }
    function test_dictation_streams_reconnect_and_stop_when_disabled() {
      dictation.statusCommand = fixture.stream('{"alt":"recording"}');
      dictation.audioCommand = fixture.stream('{"status":"connected"}');
      dictation.enabled = true;
      tryVerify(() => recordings >= 2 && audioConnections >= 2, 3000);
      dictation.enabled = false; wait(100);
      verify(!dictation.active); verify(!dictation.audioConnected); compare(dictation.energy, 0);
      const starts = recordings, connections = audioConnections;
      wait(160); compare(recordings, starts); compare(audioConnections, connections);
    }
  }
}
