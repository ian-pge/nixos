import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick

Scope {
  id: root

  property int cpuUsage: 0
  property int memoryUsage: 0
  property int diskUsage: 0
  property int brightness: 0
  property string networkType: "disconnected"
  property string networkName: "Disconnected"
  property int networkStrength: 0

  property string gpuText: "--"
  property string gpuTooltip: "GPU data unavailable"
  property string weatherText: "--°"
  property string weatherTooltip: "Weather unavailable"
  property string nixIcon: ""
  property string nixTooltip: "Checking for updates…"
  property var nixUpdates: []
  property bool nixChecking: true
  property bool updateSelectorVisible: false
  property bool updateMorphGentle: false
  property string updateTargetMonitor: ""
  property bool volumeOverlayVisible: false
  property bool brightnessOverlayVisible: false
  property bool wifiSelectorVisible: false
  property var wifiNetworks: []
  property int wifiSelectedIndex: 0
  property int wifiSelectionDirection: 1
  property bool wifiLoading: false
  property bool wifiRefreshSilent: false
  property string wifiMessage: ""
  property string wifiTargetMonitor: ""
  property bool wifiPasswordMode: false
  property string wifiPassword: ""
  property var wifiPendingNetwork: null
  property bool bluetoothSelectorVisible: false
  property string bluetoothTargetMonitor: ""
  property var bluetoothSelectorDevices: []
  property int bluetoothTab: 0
  property int bluetoothSelectedIndex: 0
  property int bluetoothSelectionDirection: 1
  property bool bluetoothSelectorLoading: false
  property bool bluetoothSelectorScanning: false
  property bool bluetoothSelectorRefreshSilent: false
  property string bluetoothSelectorMessage: ""
  property string bluetoothAction: ""
  readonly property bool centerOverlayVisible: volumeOverlayVisible
    || brightnessOverlayVisible || wifiSelectorVisible
    || bluetoothSelectorVisible || updateSelectorVisible

  onCenterOverlayVisibleChanged: setFocusedWindowBorder(centerOverlayVisible)

  Component.onCompleted: {
    setFocusedWindowBorder(false);
    refreshWifiNetworks(false, true);
    refreshBluetoothSelectorDevices(false, true);
  }

  Component.onDestruction: setFocusedWindowBorder(false)

  readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
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

  function setVolume(delta) {
    if (audio === null)
      return;
    audio.volume = Math.max(0, Math.min(1, audio.volume + delta));
  }

  function setFocusedWindowBorder(overlayActive) {
    Quickshell.execDetached(["hyprctl", "keyword", "general:col.active_border",
      overlayActive ? "rgba(888888aa)" : "rgba(33ff33ff)"]);
  }

  function showVolumeOverlay() {
    wifiSelectorVisible = false;
    bluetoothSelectorVisible = false;
    if (updateSelectorVisible)
      hideUpdateSelector();
    brightnessOverlayVisible = false;
    brightnessOverlayTimer.stop();
    volumeOverlayVisible = true;
    volumeOverlayTimer.restart();
  }

  function showBrightnessOverlay() {
    wifiSelectorVisible = false;
    bluetoothSelectorVisible = false;
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
    bluetoothSelectorVisible = false;
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
    wifiMessage = "";
    refreshWifiNetworks(false, true);
  }

  function hideWifiSelector() {
    wifiSelectorVisible = false;
    wifiPasswordMode = false;
    wifiPassword = "";
    wifiPendingNetwork = null;
    wifiMessage = "";
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

  function moveWifiSelection(delta) {
    if (wifiNetworks.length === 0)
      return;
    wifiSelectionDirection = delta >= 0 ? 1 : -1;
    wifiSelectedIndex = (wifiSelectedIndex + delta + wifiNetworks.length)
      % wifiNetworks.length;
    wifiPasswordMode = false;
    wifiPassword = "";
    wifiMessage = "";
  }

  function refreshWifiNetworks(forceRescan = false, silent = false) {
    if (wifiScanProcess.running)
      return;
    wifiRefreshSilent = silent;
    if (!silent) {
      wifiLoading = true;
      wifiMessage = "";
    }
    wifiScanProcess.command = ["bash", Quickshell.shellDir + "/scripts/wifi-networks.sh",
      forceRescan ? "yes" : "auto"];
    wifiScanProcess.running = true;
  }

  function toggleBluetoothSelector() {
    if (bluetoothSelectorVisible)
      hideBluetoothSelector();
    else
      showBluetoothSelector();
  }

  function showBluetoothSelector() {
    wifiSelectorVisible = false;
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

  function switchBluetoothTab() {
    bluetoothTab = bluetoothTab === 0 ? 1 : 0;
    bluetoothSelectedIndex = 0;
    bluetoothSelectorMessage = "";
    refreshBluetoothSelectorDevices(bluetoothTab === 1, bluetoothTab === 0);
  }

  function refreshBluetoothSelectorDevices(scan, silent = false) {
    if (bluetoothSelectorProcess.running)
      return;
    bluetoothSelectorRefreshSilent = silent;
    if (!silent) {
      bluetoothSelectorLoading = true;
      bluetoothSelectorScanning = scan;
      bluetoothSelectorMessage = "";
    }
    bluetoothSelectorProcess.command = ["bash",
      Quickshell.shellDir + "/scripts/bluetooth-devices.sh", scan ? "yes" : "no"];
    bluetoothSelectorProcess.running = true;
  }

  function activateSelectedBluetoothDevice() {
    if (bluetoothActionProcess.running)
      return;
    const devices = currentBluetoothDevices();
    if (devices.length === 0)
      return;
    const device = devices[Math.min(bluetoothSelectedIndex, devices.length - 1)];
    const connectedNow = Bluetooth.devices.values.some(candidate =>
      candidate.address === device.address && candidate.connected);
    bluetoothAction = bluetoothTab === 1
      ? "pair" : connectedNow ? "disconnect" : "connect";
    bluetoothSelectorMessage = bluetoothAction === "pair"
      ? "Pairing with " + device.name + "…"
      : bluetoothAction === "connect"
        ? "Connecting to " + device.name + "…"
        : "Disconnecting " + device.name + "…";
    bluetoothActionProcess.exec(["bluetoothctl", "--timeout", "20",
      bluetoothAction, device.address]);
  }

  function finishBluetoothAction(output) {
    const result = output.toLowerCase();
    const failed = result.includes("failed") || result.includes("not available")
      || result.includes("error");
    const succeeded = !failed && (result.includes("successful")
      || result.includes("successfully"));

    if (succeeded) {
      if (bluetoothAction === "pair") {
        bluetoothTab = 0;
        bluetoothSelectedIndex = 0;
      }
      bluetoothSelectorMessage = "";
      refreshBluetoothSelectorDevices(false, true);
    } else {
      bluetoothSelectorMessage = "Bluetooth action failed";
    }
  }

  function wifiIsSecured(network) {
    return network.security !== "" && network.security !== "--"
      && network.security.toLowerCase() !== "open";
  }

  function connectSelectedWifi() {
    if (wifiNetworks.length === 0 || wifiConnectProcess.running
        || wifiPasswordConnectProcess.running)
      return;
    const network = wifiNetworks[Math.min(wifiSelectedIndex, wifiNetworks.length - 1)];
    if (network.active) {
      hideWifiSelector();
      return;
    }

    if (wifiPasswordMode) {
      if (wifiPassword.length === 0) {
        wifiMessage = "Password required";
        return;
      }
      wifiPendingNetwork = network;
      wifiMessage = "Connecting to " + network.ssid + "…";
      wifiPasswordConnectProcess.command = ["bash",
        Quickshell.shellDir + "/scripts/wifi-connect-password.sh", network.ssid];
      wifiPasswordConnectProcess.running = true;
      return;
    }

    if (wifiIsSecured(network) && !network.known) {
      wifiPasswordMode = true;
      wifiPassword = "";
      wifiMessage = "";
      return;
    }

    wifiPendingNetwork = network;
    wifiMessage = "Connecting to " + network.ssid + "…";
    wifiConnectProcess.exec(["nmcli", "--wait", "15", "device", "wifi", "connect", network.ssid]);
  }

  function finishWifiConnection(exitCode, usedPassword) {
    if (exitCode === 0) {
      hideWifiSelector();
      refreshWifiNetworks(false, true);
      return;
    }

    if (wifiPendingNetwork !== null && wifiIsSecured(wifiPendingNetwork)) {
      wifiPasswordMode = true;
      wifiPassword = "";
      wifiMessage = usedPassword ? "Incorrect password" : "Password required";
    } else {
      wifiMessage = "Unable to connect";
    }
  }

  function toggleUpdateSelector() {
    if (updateSelectorVisible)
      hideUpdateSelector();
    else
      showUpdateSelector();
  }

  function showUpdateSelector() {
    wifiSelectorVisible = false;
    bluetoothSelectorVisible = false;
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
    command: ["bash", Quickshell.shellDir + "/scripts/system-stats.sh"]
    running: true

    stdout: SplitParser {
      onRead: data => {
        try {
          const stats = JSON.parse(data);
          root.cpuUsage = stats.cpu;
          root.memoryUsage = stats.memory;
          root.diskUsage = stats.disk;
          if (!root.brightnessOverlayVisible)
            root.brightness = stats.brightness;
          root.networkType = stats.networkType;
          root.networkName = stats.networkName;
          root.networkStrength = stats.networkStrength;
        } catch (error) {
          console.warn("Unable to parse system stats:", error);
        }
      }
    }
  }

  Process {
    id: bluetoothSelectorProcess
    command: ["bash", Quickshell.shellDir + "/scripts/bluetooth-devices.sh", "no"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.bluetoothSelectorDevices = JSON.parse(text.trim());
          const devices = root.currentBluetoothDevices();
          root.bluetoothSelectedIndex = Math.min(root.bluetoothSelectedIndex,
            Math.max(0, devices.length - 1));
        } catch (error) {
          if (!root.bluetoothSelectorRefreshSilent) {
            root.bluetoothSelectorDevices = [];
            root.bluetoothSelectorMessage = "Unable to list devices";
          }
        }
        root.bluetoothSelectorLoading = false;
        root.bluetoothSelectorScanning = false;
        root.bluetoothSelectorRefreshSilent = false;
      }
    }
  }

  Process {
    id: bluetoothActionProcess

    stdout: StdioCollector { id: bluetoothActionOutput }
    stderr: StdioCollector { id: bluetoothActionError }
    onExited: (exitCode, exitStatus) => root.finishBluetoothAction(
      bluetoothActionOutput.text + "\n" + bluetoothActionError.text)
  }

  Process {
    id: wifiScanProcess
    command: ["bash", Quickshell.shellDir + "/scripts/wifi-networks.sh", "auto"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const selectedSsid = root.wifiNetworks.length > 0
            ? root.wifiNetworks[Math.min(root.wifiSelectedIndex,
              root.wifiNetworks.length - 1)].ssid : "";
          const networks = JSON.parse(text.trim());
          root.wifiNetworks = networks;
          const refreshedIndex = networks.findIndex(network =>
            network.ssid === selectedSsid);
          root.wifiSelectedIndex = root.wifiRefreshSilent && refreshedIndex >= 0
            ? refreshedIndex : 0;
        } catch (error) {
          if (!root.wifiRefreshSilent) {
            root.wifiNetworks = [];
            root.wifiMessage = "Unable to scan networks";
          }
        }
        root.wifiLoading = false;
        root.wifiRefreshSilent = false;
      }
    }
  }

  Process {
    id: wifiConnectProcess

    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onExited: (exitCode, exitStatus) => root.finishWifiConnection(exitCode, false)
  }

  Process {
    id: wifiPasswordConnectProcess
    stdinEnabled: true

    stdout: StdioCollector {}
    stderr: StdioCollector {}
    onStarted: {
      write(root.wifiPassword + "\n");
      root.wifiPassword = "";
    }
    onExited: (exitCode, exitStatus) => root.finishWifiConnection(exitCode, true)
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
