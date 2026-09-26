import Quickshell
import Quickshell.Hyprland
import QtQuick
import "./bar"
import "./ui"
import "./features/audio"
import "./features/auth"
import "./features/brightness"
import "./features/calendar"
import "./features/dictation"
import "./features/keyboard"
import "./features/launchers"
import "./features/messenger"
import "./features/network"
import "./features/notifications"
import "./features/power"
import "./features/system"
import "./features/updates"
import "./features/workspaces"
import "./shell"

ShellRoot {
  id: desktop
  // The private composition test disables helper processes and native agents;
  // production entry keeps the exact same single-instance object graph.
  property bool servicesEnabled: true
  readonly property var services: featureRegistry
  readonly property var coordinator: panels
  readonly property var bars: barVariants.instances
  GlassController {}
  KeyboardCheatsheet {}
  WorkspaceMonitorSync {}

  BeeperData { id: messageData; enabled: desktop.servicesEnabled; demo: !desktop.servicesEnabled }
  MessengerController {
    id: messengerController
    beeperData: messageData
    blocked: authFeature.active
  }

  // References only: each feature owns its own state, commands and lifetime.
  QtObject {
    id: featureRegistry
    readonly property var audio: audioFeature
    readonly property var auth: authFeature
    readonly property var appLauncher: appLauncherFeature
    readonly property var chromeTabs: chromeTabsFeature
    readonly property var brightness: brightnessFeature
    readonly property var calendar: calendarFeature
    readonly property var dictation: dictationFeature
    readonly property var media: mediaFeature
    readonly property var network: networkFeature
    readonly property var bluetooth: bluetoothFeature
    readonly property var notifications: notificationsFeature
    readonly property var power: powerFeature
    readonly property var system: systemFeature
    readonly property var updates: updatesFeature
    readonly property var spinner: spinnerFeature
  }
  ShellCoordinator {
    id: panels
    services: featureRegistry
    messenger: messengerController
    focusedMonitor: Hyprland.focusedMonitor?.name || ""
    monitors: Hyprland.monitors.values.map(monitor => monitor.name)
  }
  ShellIntegration { services: featureRegistry; coordinator: panels; messenger: messengerController; enabled: desktop.servicesEnabled }

  AudioController { id: audioFeature; enabled: desktop.servicesEnabled; selectorVisible: panels.mode === "audio" }
  AppLauncherController { id: appLauncherFeature; onCloseRequested: panels.close("launcher") }
  ChromeTabsController { id: chromeTabsFeature; onCloseRequested: panels.close("tabs") }
  NetworkController { id: networkFeature; active: desktop.servicesEnabled && panels.mode === "wifi"; onCloseRequested: panels.close("wifi") }
  BluetoothController { id: bluetoothFeature; active: desktop.servicesEnabled && panels.mode === "bluetooth"; onCloseRequested: panels.close("bluetooth") }
  UpdateController {
    id: updatesFeature
    autoCheckEnabled: desktop.servicesEnabled
    onPresentationRequested: panels.open("updates", panels.targetMonitor)
    onCloseRequested: panels.close("updates")
  }
  PolkitController {
    id: authFeature
    serviceEnabled: desktop.servicesEnabled
    onRequestStarted: panels.beginAuthentication()
    onRequestFinished: panels.finishAuthentication()
  }
  BrightnessController {
    id: brightnessFeature
    enabled: desktop.servicesEnabled
    onFeedbackRequested: monitor => panels.showBrightness(monitor, false)
    onFeedbackUpdated: monitor => panels.brightnessUpdated(monitor)
    onFeedbackFailed: monitor => panels.brightnessFailed(monitor)
  }
  DictationController { id: dictationFeature; enabled: desktop.servicesEnabled; onActiveChanged: panels.dictationChanged() }
  MediaController {
    id: mediaFeature
    enabled: desktop.servicesEnabled
    onFeedbackRequested: monitor => panels.showMedia(monitor)
    onPlayerChanged: if (!player) panels.close("media")
  }
  CalendarController { id: calendarFeature; enabled: desktop.servicesEnabled }
  SystemController {
    id: systemFeature
    enabled: desktop.servicesEnabled
    topRequested: panels.systemProcessListsWanted
    onBrightnessSample: value => { if (panels.mode !== "brightness") brightnessFeature.sample = value; }
  }
  PowerController { id: powerFeature; enabled: desktop.servicesEnabled; telemetry: systemFeature.telemetry }
  NotificationData {
    id: notificationsFeature
    suppressNativeBeeper: messageData.connected && !messageData.demo
    suppressChatBanners: messengerController.visible
  }
  BusyGlyph {
    id: spinnerFeature
    running: updatesFeature.checking || updatesFeature.busy || networkFeature.loading || networkFeature.speedTestRunning
      || bluetoothFeature.scanning || dictationFeature.transcribing
  }

  Variants {
    id: barVariants
    model: Quickshell.screens

    Bar {
      services: featureRegistry
      coordinator: panels
      messenger: messengerController
    }
  }
}
