import Quickshell
import QtQuick

// Presentation state only: fed by the two existing persistent Rust streams.
Scope {
  id: root
  property var system: null
  property var gpu: null
  property var usbDevices: []
  property real systemUpdatedAt: 0
  property real gpuUpdatedAt: 0
  property real now: clock.date.getTime()
  property bool topRequested: false
  property int topGeneration: 0
  readonly property int topRequestId: topRequested ? topGeneration : 0
  property var processTop: null
  property var gpuTop: null
  property real processTopUpdatedAt: 0
  property real gpuTopUpdatedAt: 0
  readonly property bool processTopFresh: topRequested && processTop !== null && now - processTopUpdatedAt <= 5000
  readonly property bool gpuTopFresh: topRequested && gpuTop !== null && now - gpuTopUpdatedAt <= 5000
  readonly property bool systemFresh: system !== null && now - systemUpdatedAt <= 5000
  readonly property bool gpuFresh: gpu !== null && now - gpuUpdatedAt <= 5000

  SystemClock { id: clock; precision: SystemClock.Seconds }

  onTopRequestedChanged: {
    if (topRequested) topGeneration = topGeneration % 2147483646 + 1;
    processTop = null; gpuTop = null;
    processTopUpdatedAt = 0; gpuTopUpdatedAt = 0;
  }

  function number(value, maximum = Number.MAX_SAFE_INTEGER) {
    return typeof value === "number" && isFinite(value) && value >= 0 && value <= maximum
      ? value : null;
  }

  function processRows(rows, metric) {
    if (!Array.isArray(rows)) return null;
    const seen = new Set();
    return rows.filter(row => {
      if (row === null || typeof row !== "object" || !Number.isInteger(row.pid)
          || row.pid <= 0 || row.pid > 4294967295 || seen.has(row.pid)) return false;
      seen.add(row.pid);
      return true;
    }).slice(0, 5).map(row => ({
      pid: row.pid,
      name: typeof row.name === "string" ? row.name.replace(/[\x00-\x1f\x7f]/g, " ").slice(0, 128) : "PID " + row.pid,
      usage: number(row.usage, metric === "gpu" ? 100 : Number.MAX_SAFE_INTEGER),
      memoryBytes: number(row.memoryBytes)
    }));
  }

  function acceptTop(top, isGpu, time) {
    // Old queued stdout from a closed/reopened panel must never repopulate it.
    if (!topRequested || top?.generation !== topRequestId) return;
    if (isGpu) {
      gpuTop = {sort: top.sort === "vram" ? "vram" : "gpu",
        rows: processRows(top.rows, "gpu"), error: top.error !== undefined,
        sleeping: top.state === "sleeping"};
      gpuTopUpdatedAt = time;
    } else {
      processTop = {cpu: processRows(top.cpu, "cpu"), memory: processRows(top.memory, "memory"),
        error: top.error !== undefined};
      processTopUpdatedAt = time;
    }
  }

  function acceptSystem(report, time = Date.now()) {
    if (report === null || report.error !== undefined
        || number(report.cpu, 100) === null || number(report.memory, 100) === null) {
      invalidateSystem(time);
      return false;
    }
    const details = report.system ?? {};
    system = {
      cpu: report.cpu, memory: report.memory,
      cpuName: typeof details.cpuName === "string" ? details.cpuName : "",
      cpuTemperatureC: number(details.cpuTemperatureC, 150),
      cpuFrequencyMHz: number(details.cpuFrequencyMHz, 20000),
      memoryUsedBytes: number(details.memoryUsedBytes),
      memoryTotalBytes: number(details.memoryTotalBytes),
      swapUsedBytes: number(details.swapUsedBytes),
      swapTotalBytes: number(details.swapTotalBytes)
    };
    systemUpdatedAt = time;
    usbDevices = Array.isArray(report.usbDevices) ? report.usbDevices : [];
    acceptTop(report.top, false, time);
    return true;
  }

  function acceptGpu(report, time = Date.now()) {
    const details = report?.gpu;
    if (details === undefined || details === null || typeof details.poweredOn !== "boolean") {
      invalidateGpu(time);
      return false;
    }
    const awake = details.poweredOn;
    gpu = {
      name: typeof details.name === "string" ? details.name : "",
      poweredOn: awake,
      usage: awake ? number(details.usage, 100) : null,
      temperatureC: awake ? number(details.temperatureC, 150) : null,
      memoryUsedBytes: awake ? number(details.memoryUsedBytes) : null,
      memoryTotalBytes: awake ? number(details.memoryTotalBytes) : null
    };
    gpuUpdatedAt = time;
    if (!awake) gpuTop = null;
    acceptTop(report.top, true, time);
    return true;
  }

  function invalidateSystem(time = Date.now()) {
    usbDevices = [];
    systemUpdatedAt = 0;
    system = null;
    processTop = null; processTopUpdatedAt = 0;
  }

  function invalidateGpu(time = Date.now()) {
    gpuUpdatedAt = 0;
    gpu = null;
    gpuTop = null; gpuTopUpdatedAt = 0;
  }
}
