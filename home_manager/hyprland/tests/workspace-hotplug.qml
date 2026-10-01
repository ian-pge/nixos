import QtQuick
import Quickshell

// Only launched on the private Wayland socket by workspace-hotplug_test.mjs.
ShellRoot {
  Window { title: "Workspace test A"; visible: true; width: 240; height: 160; color: "#24273a" }
  Window { title: "Workspace test B"; visible: true; width: 240; height: 160; color: "#363a4f" }
}
