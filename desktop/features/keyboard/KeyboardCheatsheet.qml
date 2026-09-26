import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

import "./KeyboardShortcuts.js" as KeyboardShortcuts

Scope {
  id: root

  property bool shown: false
  property string targetMonitor: ""
  property int pageIndex: 0

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom" && event.data === "keyboard-cheatsheet:show") {
        root.targetMonitor = Hyprland.focusedMonitor?.name
          ?? Quickshell.screens[0]?.name ?? "";
        root.pageIndex = 0;
        root.shown = true;
      } else if (event.name === "custom" && root.shown
          && event.data === "keyboard-cheatsheet:next") {
        root.pageIndex = KeyboardShortcuts.nextPage(root.pageIndex, 1);
      } else if (event.name === "custom" && root.shown
          && event.data === "keyboard-cheatsheet:previous") {
        root.pageIndex = KeyboardShortcuts.nextPage(root.pageIndex, -1);
      } else if ((event.name === "custom" && event.data === "keyboard-cheatsheet:hide")
          || event.name === "configreloaded" || event.name === "submap") {
        root.shown = false;
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: window
      required property var modelData
      screen: modelData
      visible: root.shown && modelData.name === root.targetMonitor
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "quickshell-keyboard-cheatsheet"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // A reference sheet must leave focus and pointer input with the desktop.
      mask: Region {}
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      readonly property real fit: Math.min(1, (screen.width - 48) / sheet.implicitWidth,
        (screen.height - 80) / sheet.implicitHeight)

      // Darken only the target monitor without fading the keyboard labels.
      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.82)
      }

      KeyboardSheet {
        id: sheet
        pageIndex: root.pageIndex
        anchors.centerIn: parent
        scale: window.fit
      }
    }
  }
}
