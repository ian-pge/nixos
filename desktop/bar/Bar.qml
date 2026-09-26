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
  // Include the space above the bar so upward bounces are not clipped.
  implicitHeight: screen.height
  color: "transparent"
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 36 + barTopInset
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
    z: 2
    anchors.left: parent.left
    y: window.barTopInset
    spacing: 10
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

    Pill {
      readonly property var forecast: services.calendar.weather.days[Calendar.dateKey(services.calendar.today)]
      readonly property string weatherIcon: Calendar.weatherIcon(forecast?.code)
      textFormat: Text.StyledText
      text: [
        " " + services.calendar.timeText,
        " " + services.calendar.dateText,
        (weatherIcon !== "" ? weatherIcon + "&nbsp;" : "") + services.calendar.weather.temperatureText
      ].join("&nbsp;&nbsp;&nbsp;")
      accent: Theme.sideWeather
      forceHovered: coordinator.isOpen("calendar", window.monitorName)
      interactive: true
      onLeftClicked: coordinator.toggle("calendar", window.monitorName)
    }

    Pill {
      objectName: "systemPill"
      text: [
        " " + services.system.cpuUsage + "%",
        "  " + services.system.memoryUsage + "%",
        " " + services.system.gpuText
      ].join("   ")
      accent: Theme.sideSystem
      forceHovered: coordinator.isOpen("system", window.monitorName)
      interactive: true
      onLeftClicked: coordinator.toggle("system", window.monitorName)
    }

    Pill {
      objectName: "storagePill"
      text: " " + services.system.diskUsage + "%"
      accent: Theme.sideDisk
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
    barTopInset: window.barTopInset
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
    barTop: window.barTopInset
    workAreaTop: window.exclusiveZone
    sourceWidth: centerMorph.width
    sourceHeight: centerMorph.height
    onReturnFocusRequested: window.restoreCenterFocus()
  }

  Row {
    id: rightModules
    z: 2
    anchors.right: parent.right
    y: window.barTopInset
    spacing: 10
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

    Pill {
      visible: services.power.batteryAvailable || services.power.keyboardBatteries.length > 0
      textFormat: Text.StyledText
      text: (services.power.batteryAvailable
        ? [batteryLabel("󰌢", services.power.batteryPercent, services.power.batteryPluggedIn)] : [])
        .concat(services.power.keyboardBatteries.map(device =>
          batteryLabel("󰌌", device.percent, device.pluggedIn)))
        .join("&nbsp;&nbsp;&nbsp;")
      accent: Theme.sideBattery

      function batteryLabel(icon, percent, pluggedIn) {
        const iconColor = pluggedIn ? Theme.batteryPluggedIn
          : percent !== null && percent < 20 ? Theme.error : "";
        return (iconColor !== "" ? '<font color="' + iconColor + '">' + icon + '</font>' : icon)
          + "&nbsp;" + (percent === null ? "--" : percent) + "%";
      }
    }

    Pill {
      text: services.audio.icon() + " " + services.audio.volume + "%"
      trailingText: !services.audio.microphoneAvailable || services.audio.microphoneMuted
        ? "󰍭" : "󰍬"
      trailingInactive: !services.audio.microphoneAvailable
      accent: Theme.sideVolume
      forceHovered: coordinator.isOpen("volume", window.monitorName) || coordinator.isOpen("audio", window.monitorName)
        || (coordinator.microphoneFeedbackActive
          && window.monitorName === coordinator.microphoneFeedbackTargetMonitor)
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

    Pill {
      text: services.brightness.icon(window.monitorName) + " " + services.brightness.value(window.monitorName) + "%"
      accent: Theme.sideBrightness
      forceHovered: coordinator.isOpen("brightness", window.monitorName)
      interactive: true
      onWheelUp: services.brightness.change(5, window.monitorName)
      onWheelDown: services.brightness.change(-5, window.monitorName)
    }

    Pill {
      iconOnly: true
      text: services.updates.displayedIcon
      accent: Theme.sideUpdates
      forceHovered: coordinator.isOpen("updates", window.monitorName)
      interactive: true
      onLeftClicked: coordinator.toggle("updates", window.monitorName)
      onRightClicked: services.updates.forceStatus()
    }

    Pill {
      iconOnly: true
      text: services.network.icon()
      accent: Theme.sideNetwork
      forceHovered: coordinator.isOpen("wifi", window.monitorName)
      interactive: true
      onLeftClicked: coordinator.toggle("wifi", window.monitorName)
    }

    Pill {
      iconOnly: true
      text: services.bluetooth.connected ? "󰂯" : "󰂲"
      accent: Theme.sideBluetooth
      forceHovered: coordinator.isOpen("bluetooth", window.monitorName)
      interactive: true
      onLeftClicked: coordinator.toggle("bluetooth", window.monitorName)
    }

    Pill {
      objectName: "doNotDisturbPill"
      iconOnly: true
      text: services.notifications.doNotDisturb ? "󰂛" : "󰂚"
      accent: Theme.sideNotifications
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
