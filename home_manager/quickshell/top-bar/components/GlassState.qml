pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Keep opaque backgrounds unless the matching compositor plugin is available.
Singleton {
  id: root
  property bool enabled: false
  function refresh() { if (!probe.running) probe.running = true; }
  Component.onCompleted: refresh()
  Process {
    id: probe
    command: ["hyprctl", "liquidglass"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.enabled = JSON.parse(text).enabled === true; }
        catch (_) { root.enabled = false; }
      }
    }
    onExited: code => { if (code !== 0) root.enabled = false; }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return;
      if (event.data === "liquid-glass:ready") root.refresh();
      if (event.data === "liquid-glass:disabled") root.enabled = false;
    }
  }
}
