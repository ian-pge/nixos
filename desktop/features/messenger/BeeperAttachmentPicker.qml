import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root
  // The package replaces this source-tree command with a pinned helper.
  property var command: ["bash", Qt.resolvedUrl("../../../tools/quickshell/pick-attachment.sh").toString().replace(/^file:\/\//, "")]
  property bool completed: false
  property bool started: false
  signal finished(string path, string error)

  function open() { process.exec(command); }
  function finish(path, error) {
    if (completed) return;
    completed = true;
    finished(path, error);
  }
  Process {
    id: process
    stdout: StdioCollector { id: output }
    stderr: StdioCollector { id: errors }
    onStarted: root.started = true
    onRunningChanged: if (!running && !root.started) Qt.callLater(() => root.finish("", "Could not start the file picker."))
    onExited: (exitCode, exitStatus) => Qt.callLater(() => {
      if (exitCode !== 0 || exitStatus !== 0) {
        root.finish("", errors.text.trim() || "Could not open Yazi.");
        return;
      }
      try { root.finish(JSON.parse(output.text).path || "", ""); }
      catch (_) { root.finish("", "Could not read the file selection."); }
    })
  }
}
