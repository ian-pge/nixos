import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root
  // The package replaces this source-tree command with a pinned helper.
  property var command: ["bash", Qt.resolvedUrl("../../../tools/quickshell/pick-attachment.sh").toString().replace(/^file:\/\//, "")]
  property bool completed: false
  property bool started: false
  signal finished(var paths, string error)

  function open() { process.exec(command); }
  function finish(paths, error) {
    if (completed) return;
    completed = true;
    finished(paths, error);
  }
  Process {
    id: process
    stdout: StdioCollector { id: output }
    stderr: StdioCollector { id: errors }
    onStarted: root.started = true
    onRunningChanged: if (!running && !root.started) Qt.callLater(() => root.finish([], "Could not start the file picker."))
    onExited: (exitCode, exitStatus) => Qt.callLater(() => {
      if (exitCode !== 0 || exitStatus !== 0) {
        root.finish([], errors.text.trim() || "Could not open Yazi.");
        return;
      }
      try {
        const paths = JSON.parse(output.text).paths;
        if (!Array.isArray(paths) || paths.some(path => typeof path !== "string" || !path.startsWith("/")))
          throw new Error("Invalid selection");
        root.finish(paths, "");
      } catch (_) { root.finish([], "Could not read the file selection."); }
    })
  }
}
