import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../ui"

// Compositor integration belongs to the shell; visual components only read
// the pure Qt GlassState singleton and can be tested without desktop services.
Scope {
  id: root
  function refresh() { if (!probe.running) probe.running = true; }
  Component.onCompleted: refresh()
  Process {
    id: probe
    command: ["hyprctl", "liquidglass"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { GlassState.enabled = JSON.parse(text).enabled === true; }
        catch (_) { GlassState.enabled = false; }
      }
    }
    onExited: code => { if (code !== 0) GlassState.enabled = false; }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return;
      if (event.data === "liquid-glass:ready") root.refresh();
      if (event.data === "liquid-glass:disabled") GlassState.enabled = false;
    }
  }
}
