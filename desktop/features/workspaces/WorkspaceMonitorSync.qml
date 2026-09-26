import Quickshell
import Quickshell.Hyprland
import QtQuick

// One shared refresh for all bars. No polling or external hyprctl process.
Scope {
  id: root

  function refresh() {
    Hyprland.refreshMonitors();
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      switch (event.name) {
      case "workspacev2":
      case "focusedmon":
      case "moveworkspacev2":
      case "activespecial":
      case "monitoraddedv2":
      case "monitorremoved":
      case "configreloaded":
        // Coalesce the workspace/focus events from one switch, then ask
        // Hyprland which workspace each monitor actually displays.
        Qt.callLater(root.refresh);
        break;
      }
    }
  }
}
