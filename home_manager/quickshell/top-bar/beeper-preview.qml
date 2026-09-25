import QtQuick
import Quickshell
import "components"
import "components/Theme.js" as Theme

// Standalone local-only design preview; no API, microphone, or notifications.
ShellRoot {
  BeeperData { id: data; demo: true }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 1280; implicitHeight: 900
    title: "Messages — aperçu du design"
    color: Theme.background
    Rectangle {
      id: content
      anchors.fill: parent; color: Theme.background
      BeeperPanel { anchors.fill: parent; beeperData: data; active: true; windowFocused: content.Window.active; onCloseRequested: Qt.quit() }
    }
    Timer {
      interval: 1200; running: Quickshell.env("BEEPER_PREVIEW_SCREENSHOT") !== ""; repeat: false
      onTriggered: content.grabToImage(result => {
        if (!result.saveToFile(Quickshell.env("BEEPER_PREVIEW_SCREENSHOT"))) Qt.exit(1);
        else Qt.quit();
      })
    }
  }
}
