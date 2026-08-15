import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "components"

Scope {
  id: root

  required property var modelData
  required property var statusData

  readonly property var hyprlandMonitor: Hyprland.monitorFor(modelData)
  readonly property string monitorName: hyprlandMonitor !== null
    ? hyprlandMonitor.name : ""
  readonly property bool volumeActive: statusData.volumeOverlayVisible
    && monitorName === statusData.volumeTargetMonitor
  readonly property bool brightnessActive: statusData.brightnessOverlayVisible
    && monitorName === statusData.brightnessTargetMonitor
  readonly property bool fullscreenActive: hyprlandMonitor !== null
    && hyprlandMonitor.activeWorkspace !== null
    && hyprlandMonitor.activeWorkspace.hasFullscreen
  readonly property bool osdActive: (volumeActive || brightnessActive)
    && fullscreenActive
  property bool windowLoaded: false

  onOsdActiveChanged: {
    if (osdActive) {
      unloadTimer.stop();
      windowLoaded = true;
    } else if (windowLoaded) {
      unloadTimer.restart();
    }
  }

  Timer {
    id: unloadTimer
    interval: 380
    onTriggered: root.windowLoaded = false
  }

  // Keep the fullscreen OSD in its own native layer-shell surface. Creating a
  // separate surface avoids ever promoting the bar itself above fullscreen.
  LazyLoader {
    active: root.windowLoaded

    PanelWindow {
      id: window

      property bool presented: false

      screen: root.modelData
      anchors.top: true
      margins.top: 2
      implicitWidth: 352
      implicitHeight: 44
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-volume-brightness-osd"

      mask: Region { item: osdContent }

      Component.onCompleted: revealTimer.start()

      Connections {
        target: root

        function onOsdActiveChanged() {
          if (root.osdActive)
            revealTimer.restart();
          else
            window.presented = false;
        }
      }

      Timer {
        id: revealTimer
        interval: 16
        onTriggered: {
          if (root.osdActive)
            window.presented = true;
        }
      }

      Item {
        id: osdContent
        anchors.horizontalCenter: parent.horizontalCenter
        y: window.presented ? 8 : 0
        width: window.presented ? 280 : 352
        height: 36

        Behavior on y {
          NumberAnimation {
            duration: 360
            easing.type: Easing.OutCubic
          }
        }

        Behavior on width {
          NumberAnimation {
            duration: 360
            easing.type: Easing.OutCubic
          }
        }

        VolumeIndicator {
          anchors.fill: parent
          statusData: root.statusData
          targetMonitor: root.monitorName
          visible: root.volumeActive
        }

        BrightnessIndicator {
          anchors.fill: parent
          statusData: root.statusData
          targetMonitor: root.monitorName
          visible: root.brightnessActive
        }
      }
    }
  }
}
