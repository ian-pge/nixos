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
  property bool volumeOverlayVisible: false
  property bool brightnessOverlayVisible: false
  property bool wifiSelectorVisible: false
  property var wifiNetworks: []
  property int wifiSelectedIndex: 0
  property int wifiSelectionDirection: 1
  property bool wifiLoading: false
  property string wifiMessage: ""
  property string wifiTargetMonitor: ""
  property bool wifiPasswordMode: false
  property string wifiPassword: ""
  property var wifiPendingNetwork: null

  Component.onCompleted: refreshWifiNetworks()

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

  function showVolumeOverlay() {
    wifiSelectorVisible = false;
    brightnessOverlayVisible = false;
    brightnessOverlayTimer.stop();
    volumeOverlayVisible = true;
    volumeOverlayTimer.restart();
  }

  function showBrightnessOverlay() {
    wifiSelectorVisible = false;
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
    volumeOverlayVisible = false;
    brightnessOverlayVisible = false;
    volumeOverlayTimer.stop();
    brightnessOverlayTimer.stop();
    wifiTargetMonitor = Hyprland.focusedMonitor !== null
      ? Hyprland.focusedMonitor.name : "";
    wifiSelectorVisible = true;
    wifiMessage = "";
    refreshWifiNetworks();
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

  function refreshWifiNetworks(forceRescan = false) {
    if (wifiScanProcess.running)
      return;
    wifiLoading = true;
    wifiMessage = "";
    wifiScanProcess.command = ["bash", Quickshell.shellDir + "/wifi-networks.sh",
      forceRescan ? "yes" : "auto"];
    wifiScanProcess.running = true;
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
        Quickshell.shellDir + "/wifi-connect-password.sh", network.ssid];
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
      refreshWifiNetworks();
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

  function refreshNixStatus() {
    if (!nixStatusProcess.running)
      nixStatusProcess.running = true;
  }

  function forceNixStatus() {
    if (!nixForceProcess.running)
      nixForceProcess.running = true;
  }

  function parseNixStatus(text) {
    try {
      const status = JSON.parse(text.trim());
      root.nixIcon = status.alt === "has-updates" ? "" : "";
      root.nixTooltip = status.tooltip || "System is up to date";
    } catch (error) {
      root.nixTooltip = "Unable to check for updates";
    }
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
    command: ["bash", Quickshell.shellDir + "/system-stats.sh"]
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
    id: wifiScanProcess
    command: ["bash", Quickshell.shellDir + "/wifi-networks.sh", "auto"]

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.wifiNetworks = JSON.parse(text.trim());
          root.wifiSelectedIndex = 0;
        } catch (error) {
          root.wifiNetworks = [];
          root.wifiMessage = "Unable to scan networks";
        }
        root.wifiLoading = false;
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
    command: ["gpu-usage-waybar"]
    environment: ({ "LD_LIBRARY_PATH": "/run/opengl-driver/lib" })
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
    command: ["wttrbar", "--nerd"]
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
    command: ["nixos-update-checker"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.parseNixStatus(text)
    }
  }

  Process {
    id: nixForceProcess
    command: ["nixos-update-checker", "force"]
    stdout: StdioCollector {
      onStreamFinished: root.parseNixStatus(text)
    }
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
  }
}
