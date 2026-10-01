import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

import "../features/calendar/Calendar.js" as Calendar
import "../ui/Theme.js" as Theme
import "../shell"
import "../ui"

PanelWindow {
  id: window
  objectName: "desktopBar"
  readonly property Item capsule: centerMorph

  required property var modelData
  required property var services
  required property var coordinator
  required property var messenger

  property bool entered: false
  readonly property bool beeperActive: messengerSurface.active
  readonly property int barTopInset: 10
  readonly property int blockHeight: Theme.barSize(36)
  readonly property int capsuleTopInset: barTopInset
  readonly property var hyprlandMonitor: Hyprland.monitorFor(window.screen)
    ?? Hyprland.monitors.values.find(monitor => monitor.name === window.modelData.name)
    ?? null
  readonly property string monitorName: hyprlandMonitor !== null
    ? hyprlandMonitor.name : ""
  readonly property bool fullscreenActive: hyprlandMonitor !== null
    && hyprlandMonitor.activeWorkspace !== null
    && hyprlandMonitor.activeWorkspace.hasFullscreen
  readonly property bool keyboardSelectorActive: centerMorph.keyboardSelectorActive

  screen: modelData

  anchors {
    top: true
    left: true
    right: true
  }

  margins {
    top: 0
    left: 5
    right: 5
  }

  // Keep the layer surface geometry fixed so expanding the update card cannot
  // nudge the other bar modules. The mask leaves the unused area click-through.
  // Keep the top inset inside the same stable surface.
  implicitHeight: screen.height
  color: "transparent"
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: blockHeight + barTopInset
  // Raise this monitor's entire bar while a central widget is open. Keep it
  // above fullscreen through the closing morph, then return to the normal layer.
  WlrLayershell.layer: fullscreenActive
    && (centerMorph.overlayVisible || messengerSurface.presented || fullscreenHideDelay.running)
    ? WlrLayer.Overlay : WlrLayer.Top
  WlrLayershell.namespace: "quickshell-top-bar"
  WlrLayershell.keyboardFocus: keyboardSelectorActive
    ? WlrKeyboardFocus.Exclusive : messengerSurface.wantsKeyboard
    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  function restoreCenterFocus() {
    if (window.contentItem.Window.active) centerMorph.restoreFocus();
  }

  mask: Region {
    Region { item: leftModules }
    Region { item: centerMorph.visible ? centerMorph : null }
    Region { item: rightModules }
    Region { item: messengerSurface.presented ? messengerSurface.surfaceItem : null }
  }

  Component.onCompleted: entered = true

  Timer {
    id: fullscreenHideDelay
    interval: 360
  }

  Row {
    id: leftModules
    objectName: "leftBarModules"
    z: 2
    anchors.left: parent.left
    y: window.barTopInset
    spacing: Theme.barSize(10)
    opacity: window.entered ? 1 : 0
    transform: Translate {
      y: window.entered ? 0 : -10
      Behavior on y {
        NumberAnimation {
          duration: 420
          easing.type: Easing.OutCubic
        }
      }
    }
    Behavior on opacity { NumberAnimation { duration: 240 } }

    BarBlock {
      id: calendarBlock
      objectName: "calendarBlock"
      outlined: true
      readonly property var forecast: services.calendar.weather.days[Calendar.dateKey(services.calendar.today)]
      readonly property string weatherIcon: Calendar.weatherIcon(forecast?.code)
      accent: Theme.pink
      forceHovered: coordinator.isOpen("calendar", window.monitorName)
      interactive: true
      onLeftClicked: coordinator.toggle("calendar", window.monitorName)
      Row {
        spacing: Theme.barSize(2)
        BarCell {
          objectName: "timePill"
          textPixelSize: 17
          iconName: "clock"
          text: services.calendar.timeText
          accent: calendarBlock.accent
        }
        BarCell {
          objectName: "datePill"
          textPixelSize: 17
          iconName: "calendar-days"
          text: services.calendar.dateText
          accent: calendarBlock.accent
        }
        BarCell {
          objectName: "weatherPill"
          textPixelSize: 17
          iconName: calendarBlock.weatherIcon
          text: services.calendar.weather.temperatureText
          accent: calendarBlock.accent
        }
      }
    }

    Pill {
      objectName: "updatesPill"
      outlined: true
      y: (window.blockHeight - height) / 2
      iconOnly: true
      iconName: services.updates.displayedIcon
      accent: Theme.sideUpdates
      forceHovered: coordinator.isOpen("updates", window.monitorName)
      interactive: true
      onLeftClicked: coordinator.toggle("updates", window.monitorName)
      onRightClicked: services.updates.forceStatus()
    }

    BarBlock {
      id: connectivityBlock
      objectName: "connectivityBlock"
      circularContent: true
      accent: Theme.sideConnectivity
      Row {
        spacing: Theme.barSize(4)
        BarCell {
          objectName: "bluetoothPill"
          outlined: true
          iconOnly: true
          circular: true
          iconName: services.bluetooth.connected ? "bluetooth-connected" : "bluetooth-off"
          accent: connectivityBlock.accent
          forceHovered: coordinator.isOpen("bluetooth", window.monitorName)
          interactive: true
          onLeftClicked: coordinator.toggle("bluetooth", window.monitorName)
        }
        BarCell {
          objectName: "wifiPill"
          outlined: true
          iconOnly: true
          circular: true
          iconName: services.network.icon()
          accent: connectivityBlock.accent
          forceHovered: coordinator.isOpen("wifi", window.monitorName)
          interactive: true
          onLeftClicked: coordinator.toggle("wifi", window.monitorName)
        }
        BarCell {
          objectName: "microphonePill"
          outlined: true
          iconOnly: true
          circular: true
          iconName: !services.audio.microphoneAvailable || services.audio.microphoneMuted ? "mic-off" : "mic"
          inactive: !services.audio.microphoneAvailable
          accent: connectivityBlock.accent
          forceHovered: coordinator.microphoneFeedbackActive
            && window.monitorName === coordinator.microphoneFeedbackTargetMonitor
          interactive: true
          onLeftClicked: {
            if (services.audio.toggleMicrophoneMute()) coordinator.showMicrophoneFeedback(window.monitorName);
          }
          onRightClicked: coordinator.toggle("audio", window.monitorName)
        }
        BarCell {
          objectName: "doNotDisturbPill"
          outlined: true
          iconOnly: true
          circular: true
          iconName: services.notifications.doNotDisturb ? "bell-off" : "bell"
          accent: connectivityBlock.accent
          forceHovered: services.notifications.dndFeedbackActive
            && services.notifications.dndFeedbackTargetMonitor === window.monitorName
          interactive: true
          onLeftClicked: services.notifications.toggleDoNotDisturb(window.monitorName)
          onRightClicked: Quickshell.execDetached([
            "hyprctl", "eval",
            "local disabled = not quickshell_internal_keyboard_disabled; "
              + "hl.device({name = 'at-translated-set-2-keyboard', enabled = not disabled}); "
              + "quickshell_internal_keyboard_disabled = disabled"
          ])
        }
      }
    }

    BarBlock {
      objectName: "storageBlock"
      circularContent: true
      accent: Theme.sideDisk
      forceHovered: coordinator.isOpen("storage", window.monitorName)
      BarDial {
        objectName: "storagePill"
        iconName: "hard-drive"
        label: "Storage used"
        value: services.system.diskUsage
        accent: Theme.sideDisk
        forceHovered: coordinator.isOpen("storage", window.monitorName)
        interactive: true
        onLeftClicked: coordinator.toggle("storage", window.monitorName)
      }
    }
  }

  CentralCapsule {
    id: centerMorph
    services: window.services
    coordinator: window.coordinator
    messengerHost: messengerSurface
    monitorName: window.monitorName
    monitor: window.hyprlandMonitor
    entered: window.entered
    barTopInset: window.capsuleTopInset
    onOverlayVisibleChanged: {
      if (overlayVisible) fullscreenHideDelay.stop();
      else if (window.fullscreenActive) fullscreenHideDelay.restart();
    }
  }

  MessengerHost {
    id: messengerSurface
    anchors.fill: parent
    controller: window.messenger
    panelWindow: window
    monitorName: window.monitorName
    windowFocused: window.contentItem.Window.active
    keyboardSelectorActive: window.keyboardSelectorActive
    dictating: services.dictation.active
      && window.monitorName === coordinator.dictationTargetMonitor
    transcribing: services.dictation.transcribing
    barTop: window.capsuleTopInset
    workAreaTop: window.exclusiveZone
    sourceWidth: centerMorph.width
    sourceHeight: centerMorph.height
    onReturnFocusRequested: window.restoreCenterFocus()
  }

  Row {
    id: rightModules
    objectName: "rightBarModules"
    z: 2
    anchors.right: parent.right
    y: window.barTopInset
    spacing: Theme.barSize(10)
    opacity: window.entered ? 1 : 0
    transform: Translate {
      y: window.entered ? 0 : -10
      Behavior on y {
        NumberAnimation {
          duration: 420
          easing.type: Easing.OutCubic
        }
      }
    }
    Behavior on opacity { NumberAnimation { duration: 240 } }

    UsageBlock {
      controller: services.usage
    }

    BarBlock {
      id: batteryBlock
      objectName: "batteryBlock"
      circularContent: true
      readonly property bool warning: (services.power.batteryAvailable
        && !services.power.batteryPluggedIn && services.power.batteryPercent < 20)
        || services.power.accessoryBatteries.some(device =>
          !device.pluggedIn && device.percent !== null && device.percent < 20)
      readonly property bool pluggedIn: services.power.batteryPluggedIn
        || services.power.accessoryBatteries.some(device => device.pluggedIn)
      visible: services.power.batteryAvailable || services.power.accessoryBatteries.length > 0
      accent: warning ? Theme.error : pluggedIn ? Theme.batteryPluggedIn : Theme.sideBattery

      Row {
        spacing: Theme.barSize(4)
        BarDial {
          objectName: "batteryPill"
          visible: services.power.batteryAvailable
          iconName: "laptop"
          label: "Laptop battery"
          value: services.power.batteryPercent
          charging: services.power.batteryPluggedIn
          accent: batteryBlock.batteryColor(value, charging)
        }
        Repeater {
          model: services.power.keyboardBatteries.length
          delegate: BarDial {
            required property int index
            readonly property var device: services.power.keyboardBatteries[index] ?? null
            objectName: index === 0 ? "keyboardBatteryPill" : "keyboardBatteryPill" + index
            iconName: "keyboard"
            label: "Keyboard battery" + (services.power.keyboardBatteries.length > 1 ? " " + (index + 1) : "")
            value: device?.percent ?? null
            charging: device?.pluggedIn ?? false
            accent: batteryBlock.batteryColor(value, charging)
          }
        }
        Repeater {
          model: services.power.earbudBatteries.length
          delegate: BarDial {
            required property int index
            readonly property var device: services.power.earbudBatteries[index] ?? null
            objectName: index === 0 ? "earbudBatteryPill" : "earbudBatteryPill" + index
            iconName: "headphones"
            label: (device?.name || "Pixel Buds") + " battery"
            value: device?.percent ?? null
            charging: device?.pluggedIn ?? false
            accent: batteryBlock.batteryColor(value, charging)
          }
        }
      }

      function batteryColor(percent, pluggedIn) {
        return pluggedIn ? Theme.batteryPluggedIn
          : percent !== null && percent < 20 ? Theme.error : Theme.sideBattery;
      }
    }

    BarBlock {
      id: levelsBlock
      objectName: "levelsBlock"
      circularContent: true
      accent: Theme.sideVolume
      forceHovered: coordinator.isOpen("volume", window.monitorName)
        || coordinator.isOpen("audio", window.monitorName)
        || coordinator.isOpen("brightness", window.monitorName)
      Row {
        spacing: Theme.barSize(4)
        BarDial {
          objectName: "volumePill"
          iconName: services.audio.icon()
          label: "Volume"
          value: services.audio.volume
          muted: services.audio.muted
          accent: levelsBlock.accent
          interactive: true
          onLeftClicked: coordinator.toggle("audio", window.monitorName)
          onWheelUp: {
            services.audio.setVolume(services.audio.volumeStep);
            coordinator.showVolume(window.monitorName);
          }
          onWheelDown: {
            services.audio.setVolume(-services.audio.volumeStep);
            coordinator.showVolume(window.monitorName);
          }
        }
        BarDial {
          objectName: "brightnessPill"
          iconName: services.brightness.icon(window.monitorName)
          label: "Brightness"
          value: services.brightness.value(window.monitorName)
          accent: levelsBlock.accent
          interactive: true
          onLeftClicked: coordinator.showBrightness(window.monitorName, false)
          onWheelUp: services.brightness.change(5, window.monitorName)
          onWheelDown: services.brightness.change(-5, window.monitorName)
        }
      }
    }

    BarBlock {
      id: systemBlock
      objectName: "systemBlock"
      circularContent: true
      readonly property var telemetry: services.system.telemetry
      accent: Theme.sideSystem
      forceHovered: coordinator.isOpen("system", window.monitorName)
      Row {
        spacing: Theme.barSize(4)
        BarDial {
          objectName: "systemPill"
          iconName: "cpu"
          label: "CPU"
          value: systemBlock.telemetry.systemFresh ? systemBlock.telemetry.system.cpu : null
          accent: systemBlock.accent
          interactive: true
          onLeftClicked: coordinator.toggle("system", window.monitorName)
        }
        BarDial {
          objectName: "memoryPill"
          iconName: "memory-stick"
          label: "RAM"
          value: systemBlock.telemetry.systemFresh ? systemBlock.telemetry.system.memory : null
          accent: systemBlock.accent
          interactive: true
          onLeftClicked: coordinator.toggle("system", window.monitorName)
        }
        BarDial {
          objectName: "gpuPill"
          iconName: "gpu"
          label: "GPU"
          value: systemBlock.telemetry.gpuFresh ? systemBlock.telemetry.gpu.usage : null
          accent: systemBlock.accent
          interactive: true
          onLeftClicked: coordinator.toggle("system", window.monitorName)
        }
        BarDial {
          objectName: "vramPill"
          iconName: "microchip"
          label: "VRAM"
          value: {
            const gpu = systemBlock.telemetry.gpuFresh ? systemBlock.telemetry.gpu : null;
            if (!Number.isFinite(gpu?.memoryUsedBytes) || !Number.isFinite(gpu?.memoryTotalBytes)
                || gpu.memoryTotalBytes <= 0) return null;
            return 100 * gpu.memoryUsedBytes / gpu.memoryTotalBytes;
          }
          accent: systemBlock.accent
          interactive: true
          onLeftClicked: coordinator.toggle("system", window.monitorName)
        }
      }
    }

  }

}
