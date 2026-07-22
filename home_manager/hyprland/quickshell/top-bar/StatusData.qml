import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick

Scope {
  id: root

  property int cpuUsage: 0
  property int memoryUsage: 0
  property int diskUsage: 0
  property int brightness: 0

  property string gpuText: "--"
  property string gpuTooltip: "GPU data unavailable"
  property string weatherText: "--°"
  property string weatherTooltip: "Weather unavailable"
  property string nixIcon: ""
  property string nixTooltip: "Checking for updates…"
  property var nixUpdates: []
  property bool nixChecking: true
  property bool updateSelectorVisible: false
  property bool mediaOverlayVisible: false
  property bool mprisInitialized: false
  property bool updateMorphGentle: false
  property string updateTargetMonitor: ""
  property bool volumeOverlayVisible: false
  property bool brightnessOverlayVisible: false
  property bool wifiSelectorVisible: false
  property int wifiSelectedIndex: 0
  property string wifiSelectedSsid: ""
  property int wifiSelectionDirection: 1
  property bool wifiLoading: false
  property bool wifiRefreshSilent: false
  property string wifiMessage: ""
  property string wifiTargetMonitor: ""
  property bool wifiPasswordMode: false
  property string wifiPassword: ""
  property var wifiPendingNetwork: null
  property bool wifiConnectionUsedPassword: false
  property bool bluetoothSelectorVisible: false
  property string bluetoothTargetMonitor: ""
  property int bluetoothTab: 0
  property int bluetoothSelectedIndex: 0
  property int bluetoothSelectionDirection: 1
  property bool bluetoothSelectorLoading: false
  property bool bluetoothSelectorScanning: false
  property bool bluetoothSelectorRefreshSilent: false
  property string bluetoothSelectorMessage: ""
  property string bluetoothAction: ""
  property var bluetoothActionDevice: null
  property bool bluetoothStartedDiscovery: false
  readonly property bool centerOverlayVisible: volumeOverlayVisible
    || brightnessOverlayVisible || mediaOverlayVisible || wifiSelectorVisible
    || bluetoothSelectorVisible || updateSelectorVisible

  onCenterOverlayVisibleChanged: setFocusedWindowBorder(centerOverlayVisible)

  Component.onCompleted: setFocusedWindowBorder(false)

  Component.onDestruction: setFocusedWindowBorder(false)

  readonly property var wifiDevice: Networking.devices.values.find(device =>
    device.type === DeviceType.Wifi) ?? null
  readonly property var wiredDevice: Networking.devices.values.find(device =>
    device.type === DeviceType.Wired && device.connected) ?? null
  readonly property var wifiNetworks: {
    if (wifiDevice === null)
      return [];
    const networks = wifiDevice.networks.values.map(network => ({
      "ssid": network.name,
      "strength": Math.round(network.signalStrength * 100),
      "security": WifiSecurityType.toString(network.security),
      "active": network.connected,
      "known": network.known,
      "nativeNetwork": network
    }));
    networks.sort((left, right) => {
      if (left.active !== right.active)
        return left.active ? -1 : 1;
      if (left.strength !== right.strength)
        return right.strength - left.strength;
      return left.ssid.localeCompare(right.ssid);
    });
    return networks;
  }
  readonly property var activeWifiNetwork: wifiNetworks.find(network =>
    network.active) ?? null
  readonly property string networkType: activeWifiNetwork !== null
    ? "wifi" : wiredDevice !== null ? "ethernet"
      : !Networking.wifiEnabled ? "disabled" : "disconnected"
  readonly property string networkName: activeWifiNetwork !== null
    ? activeWifiNetwork.ssid : wiredDevice !== null ? wiredDevice.name
      : !Networking.wifiEnabled ? "Wi-Fi Off" : "Disconnected"
  readonly property int networkStrength: activeWifiNetwork !== null
    ? activeWifiNetwork.strength : wiredDevice !== null ? 100 : 0

  onWifiNetworksChanged: {
    if (wifiNetworks.length === 0) {
      wifiSelectedIndex = 0;
      wifiSelectedSsid = "";
      return;
    }
    const preservedIndex = wifiNetworks.findIndex(network =>
      network.ssid === wifiSelectedSsid);
    wifiSelectedIndex = preservedIndex >= 0 ? preservedIndex
      : Math.min(wifiSelectedIndex, wifiNetworks.length - 1);
    wifiSelectedSsid = wifiNetworks[wifiSelectedIndex].ssid;
  }

  readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
  readonly property var bluetoothSelectorDevices: Bluetooth.devices.values.map(device => ({
    "address": device.address,
    "name": device.name || device.deviceName || device.address,
    "paired": device.paired,
    "connected": device.connected,
    "nativeDevice": device
  })).sort((left, right) => {
    if (left.connected !== right.connected)
      return left.connected ? -1 : 1;
    if (left.paired !== right.paired)
      return left.paired ? -1 : 1;
    return left.name.localeCompare(right.name);
  })
  onBluetoothSelectorDevicesChanged: {
    const devices = currentBluetoothDevices();
    bluetoothSelectedIndex = Math.min(bluetoothSelectedIndex,
      Math.max(0, devices.length - 1));
  }
  readonly property bool bluetoothEnabled: bluetoothAdapter !== null
    && bluetoothAdapter.enabled
  readonly property var connectedBluetoothDevices: Bluetooth.devices.values
    .filter(device => device.connected)
  readonly property bool bluetoothConnected: connectedBluetoothDevices.length > 0
  readonly property string bluetoothTooltip: {
    if (!bluetoothEnabled)
      return "Bluetooth disabled";
    if (!bluetoothConnected)
      return bluetoothAdapter !== null ? bluetoothAdapter.name : "Bluetooth";
    return connectedBluetoothDevices.map(device => {
      const battery = device.batteryAvailable
        ? " (" + Math.round(device.battery * 100) + "%)"
        : "";
      return device.name + battery;
    }).join("\n");
  }

  readonly property var battery: UPower.displayDevice
  readonly property bool batteryAvailable: battery.ready && battery.isPresent
  readonly property int batteryPercent: batteryAvailable
    ? Math.round(battery.percentage * 100)
    : 0

  readonly property var mprisPlayer: {
    const players = Mpris.players.values.filter(player => player.canControl);
    return players.find(player => player.dbusName.includes("playerctld"))
      ?? players.find(player => player.isPlaying)
      ?? players.find(player => player.playbackState === MprisPlaybackState.Paused)
      ?? players[0] ?? null;
  }

  onMprisPlayerChanged: {
    if (mprisPlayer === null)
      hideMediaOverlay();
  }

  readonly property var audioSink: Pipewire.defaultAudioSink
  readonly property var audio: audioSink !== null ? audioSink.audio : null
  readonly property bool audioMuted: audio !== null && audio.muted
  readonly property int audioVolume: audio !== null
    ? Math.round(audio.volume * 100)
    : 0

  readonly property string timeText: Qt.formatDateTime(clock.date, "HH:mm")
  readonly property string dateText: Qt.formatDateTime(clock.date, "MMM dd yyyy")

  function batteryIcon() {
    const percentage = batteryPercent;
    const charging = battery.state === UPowerDeviceState.Charging
      || battery.state === UPowerDeviceState.PendingCharge;

    if (battery.state === UPowerDeviceState.FullyCharged)
      return "󰁹";

    if (charging) {
      if (percentage <= 10)
        return "󰂄";
      if (percentage <= 25)
        return "󰂆";
      if (percentage <= 35)
        return "󰂇";
      if (percentage <= 45)
        return "󰂈";
      if (percentage <= 65)
        return "󰂉";
      if (percentage <= 85)
        return "󰂊";
      if (percentage <= 95)
        return "󰂋";
      return "󰂅";
    }

    if (battery.state === UPowerDeviceState.Empty || percentage <= 5)
      return "󰂃";
    if (percentage <= 15)
      return "󰁺";
    if (percentage <= 25)
      return "󰁻";
    if (percentage <= 35)
      return "󰁼";
    if (percentage <= 45)
      return "󰁽";
    if (percentage <= 55)
      return "󰁾";
    if (percentage <= 65)
      return "󰁿";
    if (percentage <= 75)
      return "󰂀";
    if (percentage <= 85)
      return "󰂁";
    if (percentage <= 95)
      return "󰂂";
    return "󰁹";
  }

  function audioIcon() {
    if (audioMuted)
      return "󰖁";
    if (audioVolume < 34)
      return "󰕿";
    if (audioVolume < 67)
      return "󰖀";
    return "󰕾";
  }

  function brightnessIcon() {
    if (brightness < 34)
      return "󰃞";
    if (brightness < 67)
      return "󰃟";
    return "󰃠";
  }

  function networkIcon() {
    if (networkType === "ethernet")
      return "󰈀";
    if (networkType !== "wifi")
      return "󰤭";
    if (networkStrength < 26)
      return "󰤟";
    if (networkStrength < 51)
      return "󰤢";
    if (networkStrength < 76)
      return "󰤥";
    return "󰤨";
  }

  function showMediaOverlay() {
    if (mprisPlayer === null || wifiSelectorVisible
        || bluetoothSelectorVisible || updateSelectorVisible)
      return;
    volumeOverlayVisible = false;
    brightnessOverlayVisible = false;
    volumeOverlayTimer.stop();
    brightnessOverlayTimer.stop();
    mediaOverlayVisible = true;
    mediaOverlayTimer.restart();
  }

  function hideMediaOverlay() {
    mediaOverlayVisible = false;
    mediaOverlayTimer.stop();
  }

  function mediaPlayPause() {
    if (mprisPlayer === null)
      return;
    if (mprisPlayer.canTogglePlaying)
      mprisPlayer.togglePlaying();
    else if (mprisPlayer.isPlaying && mprisPlayer.canPause)
      mprisPlayer.pause();
    else if (!mprisPlayer.isPlaying && mprisPlayer.canPlay)
      mprisPlayer.play();
    showMediaOverlay();
  }

  function mediaNext() {
    if (mprisPlayer !== null && mprisPlayer.canGoNext) {
      mprisPlayer.next();
      showMediaOverlay();
    }
  }

  function mediaPrevious() {
    if (mprisPlayer !== null && mprisPlayer.canGoPrevious) {
      mprisPlayer.previous();
      showMediaOverlay();
    }
  }

  function setVolume(delta) {
    if (audio === null)
      return;
    audio.volume = Math.max(0, Math.min(1, audio.volume + delta));
  }

  function volumeUp() {
    setVolume(0.02);
    showVolumeOverlay();
  }

  function volumeDown() {
    setVolume(-0.02);
    showVolumeOverlay();
  }

  function toggleAudioMute() {
    if (audio === null)
      return;
    audio.muted = !audio.muted;
    showVolumeOverlay();
  }

  function setFocusedWindowBorder(overlayActive) {
    Quickshell.execDetached(["hyprctl", "keyword", "general:col.active_border",
      overlayActive ? "rgba(888888aa)" : "rgba(33ff33ff)"]);
  }

  function showVolumeOverlay() {
    hideMediaOverlay();
    wifiSelectorVisible = false;
    stopWifiScan();
    bluetoothSelectorVisible = false;
    stopBluetoothDiscovery();
    if (updateSelectorVisible)
      hideUpdateSelector();
    brightnessOverlayVisible = false;
    brightnessOverlayTimer.stop();
    volumeOverlayVisible = true;
    volumeOverlayTimer.restart();
  }

  function showBrightnessOverlay() {
    hideMediaOverlay();
    wifiSelectorVisible = false;
    stopWifiScan();
    bluetoothSelectorVisible = false;
    stopBluetoothDiscovery();
    if (updateSelectorVisible)
      hideUpdateSelector();
    volumeOverlayVisible = false;
    volumeOverlayTimer.stop();
    brightnessOverlayVisible = true;
    brightnessOverlayTimer.restart();
    brightnessRefreshProcess.exec(["brightnessctl", "-m"]);
  }

  function toggleWifiSelector() {
    if (wifiSelectorVisible)
      hideWifiSelector();
    else
      showWifiSelector();
  }

  function showWifiSelector() {
    hideMediaOverlay();
    bluetoothSelectorVisible = false;
    stopBluetoothDiscovery();
    if (updateSelectorVisible)
      hideUpdateSelector();
    volumeOverlayVisible = false;
    brightnessOverlayVisible = false;
    volumeOverlayTimer.stop();
    brightnessOverlayTimer.stop();
    wifiTargetMonitor = Hyprland.focusedMonitor !== null
      ? Hyprland.focusedMonitor.name : "";
    wifiSelectorVisible = true;
    wifiSelectedIndex = 0;
    wifiSelectedSsid = wifiNetworks.length > 0 ? wifiNetworks[0].ssid : "";
    wifiMessage = "";
    refreshWifiNetworks(false, true);
  }

  function hideWifiSelector() {
    wifiSelectorVisible = false;
    wifiPasswordMode = false;
    wifiPassword = "";
    wifiConnectionTimer.stop();
    wifiPendingNetwork = null;
    wifiConnectionUsedPassword = false;
    wifiMessage = "";
    stopWifiScan();
  }

  function cancelWifiPassword() {
    wifiPasswordMode = false;
    wifiPassword = "";
    wifiMessage = "";
  }

  function appendWifiPassword(text) {
    wifiPassword += text;
    wifiMessage = "";
  }

  function eraseWifiPassword() {
    wifiPassword = wifiPassword.slice(0, -1);
    wifiMessage = "";
  }

  function setWifiSelection(index, direction) {
    if (wifiNetworks.length === 0)
      return;
    wifiSelectionDirection = direction;
    wifiSelectedIndex = Math.max(0, Math.min(index, wifiNetworks.length - 1));
    wifiSelectedSsid = wifiNetworks[wifiSelectedIndex].ssid;
    wifiPasswordMode = false;
    wifiPassword = "";
    wifiMessage = "";
  }

  function moveWifiSelection(delta) {
    if (wifiNetworks.length === 0)
      return;
    setWifiSelection((wifiSelectedIndex + delta + wifiNetworks.length)
      % wifiNetworks.length, delta >= 0 ? 1 : -1);
  }

  function stopWifiScan() {
    wifiScanTimer.stop();
    if (wifiDevice !== null && wifiDevice.scannerEnabled)
      wifiDevice.scannerEnabled = false;
    wifiLoading = false;
    wifiRefreshSilent = false;
  }

  function refreshWifiNetworks(forceRescan = false, silent = false) {
    if (wifiDevice === null) {
      if (!silent)
        wifiMessage = "Wi-Fi device unavailable";
      return;
    }

    wifiRefreshSilent = silent;
    if (!silent) {
      wifiLoading = true;
      wifiMessage = "";
    }

    if (wifiDevice.scannerEnabled)
      wifiDevice.scannerEnabled = false;
    Qt.callLater(() => {
      if (root.wifiDevice === null)
        return;
      root.wifiDevice.scannerEnabled = true;
      wifiScanTimer.restart();
    });
  }

  function toggleBluetoothSelector() {
    if (bluetoothSelectorVisible)
      hideBluetoothSelector();
    else
      showBluetoothSelector();
  }

  function showBluetoothSelector() {
    hideMediaOverlay();
    wifiSelectorVisible = false;
    stopWifiScan();
    if (updateSelectorVisible)
      hideUpdateSelector();
    volumeOverlayVisible = false;
    brightnessOverlayVisible = false;
    volumeOverlayTimer.stop();
    brightnessOverlayTimer.stop();
    bluetoothTargetMonitor = Hyprland.focusedMonitor !== null
      ? Hyprland.focusedMonitor.name : "";
    bluetoothSelectorVisible = true;
    bluetoothTab = 0;
    bluetoothSelectedIndex = 0;
    bluetoothSelectorMessage = "";
    refreshBluetoothSelectorDevices(false, true);
  }

  function hideBluetoothSelector() {
    bluetoothSelectorVisible = false;
    bluetoothSelectorMessage = "";
    stopBluetoothDiscovery();
  }

  function currentBluetoothDevices() {
    return bluetoothSelectorDevices.filter(device => bluetoothTab === 0
      ? device.paired : !device.paired);
  }

  function moveBluetoothSelection(delta) {
    const devices = currentBluetoothDevices();
    if (devices.length === 0)
      return;
    bluetoothSelectionDirection = delta >= 0 ? 1 : -1;
    bluetoothSelectedIndex = (bluetoothSelectedIndex + delta + devices.length)
      % devices.length;
    bluetoothSelectorMessage = "";
  }

  function stopBluetoothDiscovery() {
    bluetoothScanTimer.stop();
    if (bluetoothStartedDiscovery && bluetoothAdapter !== null)
      bluetoothAdapter.discovering = false;
    bluetoothStartedDiscovery = false;
    bluetoothSelectorLoading = false;
    bluetoothSelectorScanning = false;
    bluetoothSelectorRefreshSilent = false;
  }

  function switchBluetoothTab() {
    bluetoothTab = bluetoothTab === 0 ? 1 : 0;
    bluetoothSelectedIndex = 0;
    bluetoothSelectorMessage = "";
    if (bluetoothTab === 1)
      refreshBluetoothSelectorDevices(true, false);
    else
      stopBluetoothDiscovery();
  }

  function refreshBluetoothSelectorDevices(scan, silent = false) {
    if (!scan)
      return;
    if (bluetoothAdapter === null) {
      if (!silent)
        bluetoothSelectorMessage = "Bluetooth adapter unavailable";
      return;
    }

    bluetoothSelectorRefreshSilent = silent;
    if (!silent) {
      bluetoothSelectorLoading = true;
      bluetoothSelectorScanning = true;
      bluetoothSelectorMessage = "";
    }
    if (!bluetoothAdapter.discovering) {
      bluetoothStartedDiscovery = true;
      bluetoothAdapter.discovering = true;
    }
    bluetoothScanTimer.restart();
  }

  function activateSelectedBluetoothDevice() {
    if (bluetoothActionDevice !== null)
      return;
    const devices = currentBluetoothDevices();
    if (devices.length === 0)
      return;
    const device = devices[Math.min(bluetoothSelectedIndex, devices.length - 1)];
    const nativeDevice = device.nativeDevice;
    bluetoothAction = bluetoothTab === 1
      ? "pair" : nativeDevice.connected ? "disconnect" : "connect";
    bluetoothActionDevice = nativeDevice;
    bluetoothSelectorMessage = bluetoothAction === "pair"
      ? "Pairing with " + device.name + "…"
      : bluetoothAction === "connect"
        ? "Connecting to " + device.name + "…"
        : "Disconnecting " + device.name + "…";
    bluetoothActionTimer.restart();

    if (bluetoothAction === "pair")
      nativeDevice.pair();
    else if (bluetoothAction === "connect")
      nativeDevice.connect();
    else
      nativeDevice.disconnect();
  }

  function finishBluetoothAction(succeeded) {
    bluetoothActionTimer.stop();
    if (succeeded) {
      if (bluetoothAction === "pair") {
        if (bluetoothActionDevice !== null)
          bluetoothActionDevice.trusted = true;
        bluetoothTab = 0;
        bluetoothSelectedIndex = 0;
        stopBluetoothDiscovery();
      }
      bluetoothSelectorMessage = "";
    } else {
      bluetoothSelectorMessage = "Bluetooth action failed";
    }
    bluetoothActionDevice = null;
    bluetoothAction = "";
  }

  function wifiIsSecured(network) {
    return network.security !== "" && network.security !== "--"
      && network.security.toLowerCase() !== "open";
  }

  function connectSelectedWifi() {
    if (wifiNetworks.length === 0 || wifiPendingNetwork !== null)
      return;
    const network = wifiNetworks[Math.min(wifiSelectedIndex, wifiNetworks.length - 1)];
    if (network.active) {
      hideWifiSelector();
      return;
    }

    if (wifiPasswordMode && wifiPassword.length === 0) {
      wifiMessage = "Password required";
      return;
    }

    if (!wifiPasswordMode && wifiIsSecured(network) && !network.known) {
      wifiPasswordMode = true;
      wifiPassword = "";
      wifiMessage = "";
      return;
    }

    wifiPendingNetwork = network;
    wifiConnectionUsedPassword = wifiPasswordMode;
    wifiMessage = "Connecting to " + network.ssid + "…";
    wifiConnectionTimer.restart();

    if (wifiPasswordMode) {
      network.nativeNetwork.connectWithPsk(wifiPassword);
      wifiPassword = "";
      wifiPasswordMode = false;
    } else {
      network.nativeNetwork.connect();
    }
  }

  function failWifiConnection() {
    wifiConnectionTimer.stop();
    const network = wifiPendingNetwork;
    wifiPendingNetwork = null;
    if (network !== null && wifiIsSecured(network)) {
      wifiPasswordMode = true;
      wifiPassword = "";
      wifiMessage = wifiConnectionUsedPassword
        ? "Incorrect password" : "Password required";
    } else {
      wifiMessage = "Unable to connect";
    }
    wifiConnectionUsedPassword = false;
  }

  function toggleUpdateSelector() {
    if (updateSelectorVisible)
      hideUpdateSelector();
    else
      showUpdateSelector();
  }

  function showUpdateSelector() {
    hideMediaOverlay();
    wifiSelectorVisible = false;
    stopWifiScan();
    bluetoothSelectorVisible = false;
    stopBluetoothDiscovery();
    volumeOverlayVisible = false;
    brightnessOverlayVisible = false;
    volumeOverlayTimer.stop();
    brightnessOverlayTimer.stop();
    updateTargetMonitor = Hyprland.focusedMonitor !== null
      ? Hyprland.focusedMonitor.name : "";
    updateMorphGentle = true;
    updateMorphTimer.restart();
    updateSelectorVisible = true;
  }

  function hideUpdateSelector() {
    updateMorphGentle = true;
    updateMorphTimer.restart();
    updateSelectorVisible = false;
  }

  function startNixUpdate() {
    hideUpdateSelector();
    Quickshell.execDetached(["ghostty", "-e", "quickshell-update-installer"]);
  }

  function refreshNixStatus() {
    if (!nixStatusProcess.running)
      nixStatusProcess.running = true;
  }

  function forceNixStatus() {
    if (!nixForceProcess.running) {
      nixChecking = true;
      nixForceProcess.running = true;
    }
  }

  function parseNixStatus(text) {
    try {
      const status = JSON.parse(text.trim());
      if (Array.isArray(status.updates)) {
        root.nixUpdates = status.updates;
        root.nixIcon = status.hasUpdates ? "" : "";
        root.nixTooltip = status.hasUpdates
          ? status.updates.map(update => update.name + ": " + update.date).join("\n")
          : status.message || "System is up to date";
      } else {
        // Compatibility with the preserved Waybar helper cache format.
        root.nixIcon = status.alt === "has-updates" ? "" : "";
        root.nixTooltip = status.tooltip || "System is up to date";
        const lines = status.alt === "has-updates"
          ? root.nixTooltip.split("\n").filter(line => line.trim() !== "") : [];
        root.nixUpdates = lines.map(line => {
          const separator = line.lastIndexOf(": ");
          return separator >= 0
            ? { "name": line.slice(0, separator), "date": line.slice(separator + 2) }
            : { "name": line, "date": "" };
        });
      }
    } catch (error) {
      root.nixUpdates = [];
      root.nixTooltip = "Unable to check for updates";
    }
    root.nixChecking = false;
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }

  Process {
    id: systemStatsProcess
    command: ["quickshell-system-stats"]
    running: true

    stdout: SplitParser {
      onRead: data => {
        try {
          const stats = JSON.parse(data);
          if (stats.error !== undefined) {
            console.warn("System telemetry error:", stats.error);
            return;
          }
          root.cpuUsage = stats.cpu;
          root.memoryUsage = stats.memory;
          root.diskUsage = stats.disk;
          if (!root.brightnessOverlayVisible)
            root.brightness = stats.brightness;
        } catch (error) {
          console.warn("Unable to parse system stats:", error);
        }
      }
    }
  }

  Connections {
    target: root.mprisPlayer

    function onPostTrackChanged() {
      if (root.mprisInitialized)
        root.showMediaOverlay();
    }
  }

  Connections {
    target: root.wifiPendingNetwork !== null
      ? root.wifiPendingNetwork.nativeNetwork : null

    function onConnectedChanged() {
      if (root.wifiPendingNetwork !== null
          && root.wifiPendingNetwork.nativeNetwork.connected) {
        wifiConnectionTimer.stop();
        root.wifiPendingNetwork = null;
        root.wifiConnectionUsedPassword = false;
        root.hideWifiSelector();
      }
    }

    function onConnectionFailed(reason) {
      root.failWifiConnection();
    }
  }

  Connections {
    target: root.bluetoothActionDevice

    function onConnectedChanged() {
      if (root.bluetoothActionDevice === null)
        return;
      if (root.bluetoothAction === "connect" && root.bluetoothActionDevice.connected)
        root.finishBluetoothAction(true);
      else if (root.bluetoothAction === "disconnect"
          && !root.bluetoothActionDevice.connected)
        root.finishBluetoothAction(true);
    }

    function onPairedChanged() {
      if (root.bluetoothAction === "pair" && root.bluetoothActionDevice !== null
          && root.bluetoothActionDevice.paired)
        root.finishBluetoothAction(true);
    }
  }

  Timer {
    id: wifiScanTimer
    interval: 5000
    onTriggered: root.stopWifiScan()
  }

  Timer {
    id: wifiConnectionTimer
    interval: 20000
    onTriggered: root.failWifiConnection()
  }

  Timer {
    id: bluetoothScanTimer
    interval: 5000
    onTriggered: root.stopBluetoothDiscovery()
  }

  Timer {
    id: bluetoothActionTimer
    interval: 20000
    onTriggered: root.finishBluetoothAction(false)
  }

  Process {
    id: brightnessRefreshProcess

    stdout: StdioCollector {
      onStreamFinished: {
        const fields = text.trim().split(",");
        if (fields.length >= 4)
          root.brightness = parseInt(fields[3].replace("%", ""), 10);
      }
    }
  }

  Process {
    id: gpuProcess
    command: ["quickshell-gpu-monitor"]
    running: true

    stdout: SplitParser {
      onRead: data => {
        try {
          const gpu = JSON.parse(data);
          root.gpuText = gpu.text || "--";
          root.gpuTooltip = gpu.tooltip || "GPU data unavailable";
        } catch (error) {
          console.warn("Unable to parse GPU data:", error);
        }
      }
    }
  }

  Process {
    id: weatherProcess
    command: ["quickshell-weather"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const weather = JSON.parse(text.trim());
          root.weatherText = (weather.text || "--") + "°";
          root.weatherTooltip = (weather.tooltip || "Weather unavailable")
            .replace(/<[^>]*>/g, "");
        } catch (error) {
          root.weatherTooltip = "Unable to retrieve weather";
        }
      }
    }
  }

  Timer {
    interval: 3600000
    running: true
    repeat: true
    onTriggered: {
      if (!weatherProcess.running)
        weatherProcess.running = true;
    }
  }

  Process {
    id: nixStatusProcess
    command: ["quickshell-update-checker"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.parseNixStatus(text)
    }
  }

  Process {
    id: nixForceProcess
    command: ["quickshell-update-checker", "force"]
    stdout: StdioCollector {
      onStreamFinished: root.parseNixStatus(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    onTriggered: root.mprisInitialized = true
  }

  Timer {
    id: mediaOverlayTimer
    interval: 4000
    onTriggered: root.mediaOverlayVisible = false
  }

  Timer {
    id: updateMorphTimer
    interval: 360
    onTriggered: root.updateMorphGentle = false
  }

  Timer {
    id: volumeOverlayTimer
    interval: 2000
    onTriggered: root.volumeOverlayVisible = false
  }

  Timer {
    id: brightnessOverlayTimer
    interval: 2000
    onTriggered: root.brightnessOverlayVisible = false
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refreshNixStatus()
  }

  IpcHandler {
    target: "topbar"

    function refreshNix() {
      root.refreshNixStatus();
    }

    function mediaPlayPause() {
      root.mediaPlayPause();
    }

    function mediaNext() {
      root.mediaNext();
    }

    function mediaPrevious() {
      root.mediaPrevious();
    }

    function volumeUp() {
      root.volumeUp();
    }

    function volumeDown() {
      root.volumeDown();
    }

    function toggleAudioMute() {
      root.toggleAudioMute();
    }

    function showVolume() {
      root.showVolumeOverlay();
    }

    function showBrightness() {
      root.showBrightnessOverlay();
    }

    function toggleWifi() {
      root.toggleWifiSelector();
    }

    function toggleBluetooth() {
      root.toggleBluetoothSelector();
    }

    function toggleUpdates() {
      root.toggleUpdateSelector();
    }
  }
}
