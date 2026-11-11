import Quickshell
import Quickshell.Hyprland
import QtQuick

// One shared refresh for all bars. No polling or external hyprctl process.
Scope {
  id: root

  function refresh() {
    Hyprland.refreshMonitors();
  }

  function refreshWindowModes() {
    // The exact fullscreen/maximized mode lives in the client IPC snapshot.
    // Refresh on events, including direct transitions between those modes.
    Hyprland.refreshToplevels();
  }
  Component.onCompleted: refreshWindowModes()

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      switch (event.name) {
      case "fullscreen":
        Qt.callLater(root.refreshWindowModes);
        break;
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
