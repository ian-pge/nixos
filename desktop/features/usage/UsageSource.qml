import Quickshell
import Quickshell.Io
import QtQuick

// One short JSON-lines conversation with an official CLI. It starts only on
// request, accepts one answer, then closes stdin so the CLI exits by itself.
Scope {
  id: root
  property string name: ""
  property list<string> command: []
  property var protocol: null
  property int timeout: 30000
  property int killDelay: 3000
  property string workingDirectory: Quickshell.workingDirectory
  property var snapshot: null
  property string error: ""
  property real updatedAt: 0
  // From start() until the process has exited: Process.running only turns
  // true on the next event loop iteration, too late to guard a second start.
  property bool loading: false
  property int run: 0
  property var context: ({})
  property bool answered: false
  property bool started: false

  function start() {
    if (loading || protocol === null || command.length === 0) return false;
    loading = true;
    run += 1; context = {}; answered = false; started = false; error = "";
    process.stdinEnabled = true;
    deadline.restart();
    process.running = true;
    return true;
  }
  function send(messages) {
    for (const message of messages) process.write(JSON.stringify(message) + "\n");
  }
  function complete(result) {
    answered = true;
    deadline.stop();
    if (result.error) {
      error = result.error;
      if (result.detail) console.warn(name + " usage:", result.detail);
    } else {
      snapshot = result.snapshot;
      error = "";
      updatedAt = Date.now();
    }
  }
  function accept(line) {
    if (answered) return;
    let message;
    try { message = JSON.parse(line); } catch (_) { return; }
    const step = protocol.step(message, context);
    if (!step) return;
    if (step.send) send(step.send);
    if (!step.done) return;
    complete(step);
    process.stdinEnabled = false;
    exitGrace.restart();
  }
  function terminate() {
    if (!process.running) return;
    process.running = false;
    forceStop.restart();
  }
  function stopped() {
    if (!answered) complete({error: name + " s’est arrêté sans répondre"});
    loading = false;
  }

  Process {
    id: process
    command: root.command
    workingDirectory: root.workingDirectory
    stdinEnabled: true
    onStarted: {
      root.started = true;
      root.send(root.protocol.opening());
    }
    stdout: SplitParser { onRead: line => root.accept(line) }
    // Deferred like UpdateCommand, so a final stdout line is read first.
    onExited: {
      exitGrace.stop(); forceStop.stop();
      Qt.callLater(root.stopped);
    }
    // A missing executable never starts nor exits.
    onRunningChanged: {
      if (running || root.started || !root.loading) return;
      root.complete({error: root.name + " introuvable"});
      root.stopped();
    }
  }
  Timer {
    id: deadline
    interval: root.timeout
    onTriggered: {
      if (!root.answered) root.complete({error: "Délai dépassé"});
      root.terminate();
    }
  }
  // An answered CLI normally exits on end of input within a second.
  Timer { id: exitGrace; interval: 5000; onTriggered: root.terminate() }
  // SIGTERM first; a CLI that ignores it must not block later refreshes.
  Timer {
    id: forceStop
    interval: root.killDelay
    onTriggered: if (process.running) process.signal(9)
  }
}
