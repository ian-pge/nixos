import Quickshell
import Quickshell.Io
import QtQuick
import "components/AudioRoutes.js" as AudioRoutes

Scope {
  id: root
  property bool enabled: false
  property var unavailableNames: ({})
  property var objects: ({})

  // Quickshell's Pipewire API does not expose device routes yet. Subscribe
  // while the selector is open so jack changes update it without polling.
  Process {
    id: monitor
    command: ["pw-dump", "--monitor", "--no-colors"]
    running: root.enabled && !retry.running
    onStarted: root.objects = ({})
    stdout: SplitParser {
      splitMarker: "\n]\n"
      onRead: data => {
        try {
          AudioRoutes.updateObjects(root.objects, JSON.parse(data + "\n]"));
          root.unavailableNames = AudioRoutes.unavailableSources(root.objects);
        } catch (error) {
          console.warn("Unable to read audio route availability:", error);
        }
      }
    }
    onExited: {
      if (root.enabled) {
        root.unavailableNames = ({});
        retry.restart();
      }
    }
  }

  Timer {
    id: retry
    interval: 1000
  }
}
