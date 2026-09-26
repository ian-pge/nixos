import QtQuick
import Quickshell
import Quickshell.Io

// Process adapter: controllers and tests share this small, generation-tagged
// interface. Deferred completion lets the final stdout line arrive first.
Scope {
  id: root
  readonly property bool running: process.running
  property int generation: 0
  property bool captureOutput: false
  property string output: ""
  signal lineRead(string line, int generation)
  signal finished(int exitCode, int exitStatus, string output, int generation)

  function exec(command, requestGeneration) {
    generation = requestGeneration;
    output = "";
    process.exec(command);
  }

  function write(text) { process.write(text); }

  Process {
    id: process
    stdinEnabled: true
    stdout: SplitParser {
      onRead: line => {
        if (root.captureOutput)
          root.output += line + "\n";
        root.lineRead(line, root.generation);
      }
    }
    onExited: (exitCode, exitStatus) => {
      const requestGeneration = root.generation;
      Qt.callLater(() => root.finished(exitCode, exitStatus,
        root.output, requestGeneration));
    }
  }
}
