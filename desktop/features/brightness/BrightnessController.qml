import Quickshell
import Quickshell.Io
import QtQuick

// Serialized per-monitor helper writes, independent of the shell's OSD lifetime.
Scope {
  id: root
  property bool enabled: true
  property list<string> command: ["quickshell-brightness"]
  property var executor: helper
  property int sample: 0
  property var pendingChanges: []
  property var values: ({})
  property var states: ({})
  property int generation: 0
  property int requestGeneration: 0
  property string requestMonitor: ""
  signal feedbackRequested(string monitor)
  signal feedbackUpdated(string monitor)
  signal feedbackFailed(string monitor)
  signal stateReset()
  onEnabledChanged: {
    if (!enabled) { dispatchTimer.stop(); helper.running = false; reset(); }
    else dispatch();
  }

  function value(monitor) { return values[monitor] ?? sample; }
  function icon(monitor = "") {
    const level = value(monitor);
    return level < 34 ? "󰃞" : level < 67 ? "󰃟" : "󰃠";
  }
  function change(delta, monitor) {
    if (!Number.isFinite(delta) || delta === 0 || !monitor) return;
    feedbackRequested(monitor);
    queueChange(monitor, Math.round(delta));
  }

  function parseStatus(text) {
    if (requestGeneration !== generation)
      return;
    try {
      const status = JSON.parse(text);
      if (typeof status.monitor !== "string"
          || typeof status.brightness !== "number"
          || !isFinite(status.brightness))
        return;
      const states = Object.assign({}, root.states);
      states[status.monitor] = status;
      root.states = states;
      // A completed write must not erase newer keypresses shown in the OSD.
      let value = Math.max(0, Math.min(100, status.brightness));
      for (const change of pendingChanges) {
        if (change.monitor === status.monitor) {
          for (const delta of change.steps)
            value = Math.max(0, Math.min(100, value + delta));
        }
      }
      const values = Object.assign({}, root.values);
      values[status.monitor] = value;
      root.values = values;
      feedbackUpdated(status.monitor);
    } catch (error) {
      console.warn("Cannot read monitor brightness:", text);
    }
  }

  function queueChange(monitor, delta) {
    if (monitor === "")
      return;
    const queue = pendingChanges.slice();
    const index = queue.findIndex(change => change.monitor === monitor);
    const steps = index >= 0 ? queue[index].steps.concat([delta]) : [delta];
    // Keep every direction reversal for correct clamping, but send only the
    // final level after the external monitor's key-repeat burst has ended.
    const internal = /^(eDP|LVDS|DSI)-/.test(monitor);
    const deadline = Date.now() + (internal || delta === 0 ? 0 : 180);
    const change = {monitor: monitor, steps: steps, deadline: deadline};
    if (index >= 0)
      queue[index] = change;
    else
      queue.push(change);
    pendingChanges = queue;
    if (delta !== 0 && values[monitor] !== undefined) {
      const values = Object.assign({}, root.values);
      values[monitor] = Math.max(0, Math.min(100, values[monitor] + delta));
      root.values = values;

    }
    dispatch();
  }

  function dispatch() {
    if (!enabled || executor.running || pendingChanges.length === 0)
      return;
    dispatchTimer.stop();
    const queue = pendingChanges.slice();
    queue.sort((a, b) => a.deadline - b.deadline);
    const change = queue[0];
    const remaining = change.deadline - Date.now();
    if (remaining > 0) {
      dispatchTimer.interval = remaining;
      dispatchTimer.start();
      return;
    }
    queue.shift();
    pendingChanges = queue;
    requestGeneration = generation;
    requestMonitor = change.monitor;
    executor.exec([
      ...command, change.monitor, JSON.stringify(change.steps),
      JSON.stringify(states[change.monitor] || null)
    ]);
  }

  function reset() {
    generation++;
    states = ({});
    values = ({});
    pendingChanges = [];
    dispatchTimer.stop();
    stateReset();
  }

  function fail() {
    if (requestGeneration !== generation)
      return;
    const monitor = requestMonitor;
    const states = Object.assign({}, root.states);
    const values = Object.assign({}, root.values);
    delete states[monitor];
    delete values[monitor];
    root.states = states;
    root.values = values;
    pendingChanges = pendingChanges.filter(change => change.monitor !== monitor);
    feedbackFailed(monitor);
  }

  Process {
    id: helper
    stdout: StdioCollector { onStreamFinished: root.parseStatus(text) }
    onExited: (exitCode, exitStatus) => {
      if (exitCode !== 0) { console.warn("Monitor brightness command failed:", exitCode); root.fail(); }
      Qt.callLater(root.dispatch);
    }
  }
  Timer { id: dispatchTimer; onTriggered: root.dispatch() }
}
