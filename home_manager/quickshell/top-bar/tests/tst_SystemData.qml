import Quickshell
import QtQuick
import QtTest

ShellRoot {
  id: root
  property var data: null
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../SystemData.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString()); Qt.exit(1); return;
    }
    data = component.createObject(root);
  }
  TestResult { id: results }
  TestCase {
    name: "SystemData"
    when: root.data !== null
    function cleanupTestCase() {
      console.log("SystemData: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount > 0 ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function init() {
      root.data.system = null; root.data.gpu = null;
      root.data.topRequested = false;
      root.data.processTop = null; root.data.gpuTop = null;
      root.data.now = 100000;
    }
    function test_zero_is_valid_and_missing_details_are_null() {
      verify(root.data.acceptSystem({cpu: 0, memory: 0}, 100000));
      verify(root.data.systemFresh);
      compare(root.data.system.cpu, 0);
      compare(root.data.system.cpuTemperatureC, null);
      verify(root.data.acceptGpu({gpu: {poweredOn: true, usage: 0, temperatureC: 0}}, 100000));
      compare(root.data.gpu.usage, 0);
      compare(root.data.gpu.temperatureC, 0);
      compare(root.data.gpu.memoryUsedBytes, null);
    }
    function test_usb_presence_expires_and_clears_on_unplug_or_stream_failure() {
      const keyboard = {vendorId: "9d5b", productId: "2565", serial: "test"};
      verify(root.data.acceptSystem({cpu: 0, memory: 0, usbDevices: [keyboard]}, 100000));
      compare(root.data.usbDevices.length, 1);
      verify(root.data.systemFresh);
      root.data.now = 106000;
      verify(!root.data.systemFresh);
      root.data.acceptSystem({cpu: 0, memory: 0, usbDevices: []}, 106000);
      compare(root.data.usbDevices.length, 0);
      root.data.acceptSystem({cpu: 0, memory: 0, usbDevices: [keyboard]}, 106000);
      root.data.invalidateSystem();
      compare(root.data.usbDevices.length, 0);
      root.data.acceptSystem({cpu: 0, memory: 0}, 106000);
      compare(root.data.usbDevices.length, 0);
    }
    function test_sleeping_gpu_is_not_zero_percent() {
      verify(root.data.acceptGpu({gpu: {name: "Test", poweredOn: false, usage: 87}}, 100000));
      verify(root.data.gpuFresh);
      compare(root.data.gpu.usage, null);
      verify(!root.data.gpu.poweredOn);
    }
    function test_native_gpu_reports_sleep_error_and_recovery() {
      const active = JSON.parse('{"text":"0%|13%","gpu":{"poweredOn":true,"name":"Test NVIDIA","usage":0,"temperatureC":42,"memoryUsedBytes":536870912,"memoryTotalBytes":4294967296}}');
      verify(root.data.acceptGpu(active, 100000));
      compare(root.data.gpu.name, "Test NVIDIA");
      compare(root.data.gpu.memoryUsedBytes, 536870912);
      compare(root.data.gpu.memoryTotalBytes, 4294967296);
      verify(root.data.acceptGpu(JSON.parse('{"text":"Off","gpu":{"poweredOn":false,"name":"Test NVIDIA","usage":null,"temperatureC":null,"memoryUsedBytes":null,"memoryTotalBytes":null}}'), 101000));
      verify(root.data.gpuFresh);
      verify(!root.data.gpu.poweredOn);
      compare(root.data.gpu.memoryUsedBytes, null);
      verify(!root.data.acceptGpu(JSON.parse('{"text":"--","gpu":null,"error":"GPU telemetry unavailable: driver unavailable"}'), 102000));
      verify(!root.data.gpuFresh);
      compare(root.data.gpu, null);
      root.data.now = 132000;
      verify(root.data.acceptGpu(active, 132000));
      verify(root.data.gpuFresh);
    }
    function test_top_generations_close_reopen_and_stale_data() {
      root.data.topRequested = true;
      const generation = root.data.topRequestId;
      const rows = [{pid: 42, name: "test", usage: 200, memoryBytes: 1024}];
      const top = {generation, cpu: rows, memory: rows};
      root.data.acceptSystem({cpu: 5, memory: 10, top}, 100000);
      verify(root.data.processTopFresh);
      compare(root.data.processTop.cpu[0].usage, 200);
      root.data.acceptSystem({cpu: 6, memory: 10}, 101000);
      verify(root.data.processTopFresh);
      compare(root.data.processTopUpdatedAt, 100000);
      root.data.now = 106000;
      verify(!root.data.processTopFresh);
      root.data.topRequested = false;
      compare(root.data.topRequestId, 0);
      compare(root.data.processTop, null);
      root.data.acceptTop(top, false, 106000);
      compare(root.data.processTop, null);
      root.data.topRequested = true;
      verify(root.data.topRequestId !== generation);
      root.data.acceptTop(top, false, 106000);
      compare(root.data.processTop, null);
      root.data.acceptTop({generation: root.data.topRequestId, cpu: null, memory: rows}, false, 106000);
      verify(root.data.processTopFresh);
      compare(root.data.processTop.cpu, null);
      root.data.invalidateSystem();
      compare(root.data.processTop, null);
    }
    function test_top_rows_are_bounded_validated_and_gpu_fallback_is_explicit() {
      const rows = [null, {pid:-1}, {pid:1, name:"zero", usage:0}, {pid:1, usage:10},
        {pid:2, name:"bad\nname", usage:NaN, memoryBytes:-1}];
      for (let pid=3; pid<10; pid++) rows.push({pid, name:"x", usage:200});
      const filtered = root.data.processRows(rows, "gpu");
      compare(filtered.length, 5);
      compare(filtered[0].usage, 0);
      compare(filtered[1].name, "bad name");
      compare(filtered[1].memoryBytes, null);
      compare(filtered[2].usage, null);
      root.data.topRequested = true;
      root.data.acceptGpu({gpu:{poweredOn:true,usage:10},
        top:{generation:root.data.topRequestId,sort:"vram",rows}},100000);
      verify(root.data.gpuTopFresh);
      compare(root.data.gpuTop.sort, "vram");
      root.data.acceptGpu({gpu:{poweredOn:false}},101000);
      compare(root.data.gpuTop, null);
    }
    function test_bad_samples_and_exit_do_not_look_live() {
      root.data.acceptSystem({cpu: 55, memory: 50}, 100000);
      verify(!root.data.acceptSystem({error: "disconnected"}, 101000));
      verify(!root.data.systemFresh);
      compare(root.data.processTop, null);
      for (const cpu of [null, "20", NaN, Infinity, -1, 101])
        verify(!root.data.acceptSystem({cpu: cpu, memory: 50}, 101000));
      root.data.acceptGpu({gpu: {poweredOn: true, usage: 30}}, 100000);
      root.data.invalidateGpu(101000);
      verify(!root.data.gpuFresh);
      compare(root.data.gpuTop, null);
    }
    function test_stream_timeout_and_recovery() {
      root.data.acceptSystem({cpu: 55, memory: 50}, 100000);
      root.data.acceptGpu({gpu: {poweredOn: true, usage: 30}}, 100000);
      root.data.now = 106000;
      verify(!root.data.systemFresh && !root.data.gpuFresh);
      root.data.acceptSystem({cpu: 25, memory: 50}, 106000);
      verify(root.data.systemFresh);
      verify(!root.data.gpuFresh);
    }
    function test_optional_metrics_are_validated() {
      root.data.acceptSystem({cpu: 5, memory: 50, system: {
        cpuTemperatureC: 900, cpuFrequencyMHz: "4000", memoryUsedBytes: -1,
        memoryTotalBytes: 4294967296, swapUsedBytes: 0, swapTotalBytes: 0
      }}, 100000);
      compare(root.data.system.cpuTemperatureC, null);
      compare(root.data.system.cpuFrequencyMHz, null);
      compare(root.data.system.memoryUsedBytes, null);
      compare(root.data.system.memoryTotalBytes, 4294967296);
      compare(root.data.system.swapUsedBytes, 0);
    }
  }
}
