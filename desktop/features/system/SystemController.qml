import Quickshell
import Quickshell.Io
import QtQuick

// Persistent telemetry collectors; the shell supplies only subscription demand.
Scope {
  id: root
  property bool enabled: true
  property bool topRequested: false
  property list<string> statsCommand: ["quickshell-system-stats"]
  property list<string> gpuCommand: ["quickshell-gpu-monitor"]
  property int statsRestartDelay: 5000
  property int gpuRestartDelay: 30000
  readonly property var telemetry: model
  property int cpuUsage: 0
  property int memoryUsage: 0
  property int diskUsage: 0
  property string gpuText: "--"
  readonly property var usbDevices: model.usbDevices
  signal brightnessSample(int value)
  onEnabledChanged: {
    statsRestart.stop(); gpuRestart.stop();
    statsProcess.running = enabled; gpuProcess.running = enabled;
    if (!enabled) { model.invalidateSystem(); model.invalidateGpu(); gpuText = "--"; }
  }
  SystemData { id: model; topRequested: root.topRequested }
  Connections { target: model; function onTopRequestIdChanged() { Qt.callLater(root.syncSubscriptions); } }
  function sendSubscription(process) { process.write(model.topRequestId + "\n"); }
  function syncSubscriptions() {
    if (!enabled) return;
    sendSubscription(statsProcess); sendSubscription(gpuProcess);
  }
  function acceptSystem(line) {
    try {
      const stats = JSON.parse(line);
      if (!model.acceptSystem(stats)) return;
      cpuUsage = stats.cpu; memoryUsage = stats.memory;
      if (typeof stats.disk === "number" && isFinite(stats.disk)) diskUsage = stats.disk;
      if (typeof stats.brightness === "number" && isFinite(stats.brightness)) brightnessSample(stats.brightness);
    } catch (error) {
      console.warn("Unable to parse system stats:", error);
      model.invalidateSystem();
    }
  }
  function acceptGpu(line) {
    try {
      const gpu = JSON.parse(line);
      model.acceptGpu(gpu); gpuText = gpu.text || "--";
    } catch (error) {
      console.warn("Unable to parse GPU data:", error);
      model.invalidateGpu();
    }
  }
  Process {
    id: statsProcess
    command: root.statsCommand; running: root.enabled; stdinEnabled: true
    onStarted: root.sendSubscription(statsProcess)
    stdout: SplitParser { onRead: data => root.acceptSystem(data) }
    onExited: { model.invalidateSystem(); if (root.enabled) statsRestart.restart(); }
  }
  Timer { id: statsRestart; interval: root.statsRestartDelay; onTriggered: if (root.enabled) statsProcess.running = true }
  Process {
    id: gpuProcess
    command: root.gpuCommand; running: root.enabled; stdinEnabled: true
    onStarted: root.sendSubscription(gpuProcess)
    stdout: SplitParser { onRead: data => root.acceptGpu(data) }
    onExited: { model.invalidateGpu(); root.gpuText = "--"; if (root.enabled) gpuRestart.restart(); }
  }
  Timer { id: gpuRestart; interval: root.gpuRestartDelay; onTriggered: if (root.enabled) gpuProcess.running = true }
}
