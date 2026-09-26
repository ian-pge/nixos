import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// Owns connectivity and transient selector state, never shell surfaces or monitors.
Scope {
  id: root
  property bool active: false
  property var devices: Networking.devices.values
  property bool wifiEnabled: Networking.wifiEnabled
  property var speedTestCommand: ["quickshell-speedtest"]
  signal closeRequested()

  property int selectedIndex: 0
  property string selectedKey: ""
  property int selectionDirection: 1
  property bool loading: false
  property string message: ""
  property bool passwordMode: false
  property string password: ""
  property var pendingNetwork: null
  property bool connectionUsedPassword: false
  property bool speedTestExpanded: false
  property bool speedTestRunning: false
  property bool speedTestHasResult: false
  property string speedTestMessage: ""
  property string speedTestPing: "--"
  property string speedTestDownload: "--"
  property string speedTestUpload: "--"
  property string speedTestPhase: ""
  property string speedTestLiveValue: ""
  property real speedTestProgress: 0
  property int speedTestGeneration: 0
  property var speedTestProcess: null
  property var scanDevice: null
  property bool startedScan: false
  readonly property var wifiDevice: devices.find(device =>
    device.type === DeviceType.Wifi) ?? null
  readonly property var wiredDevice: devices.find(device =>
    device.type === DeviceType.Wired && device.connected) ?? null
  readonly property string wiredConnectionLabel: wiredDevice !== null
    ? wiredDevice.name : ""
  readonly property var wifiNetworks: {
    if (wifiDevice === null)
      return [];
    const networks = wifiDevice.networks.values.map(network => ({
      "key": "wifi:" + network.name,
      "type": "wifi",
      "label": network.name,
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
  readonly property var entries: {
    if (wiredDevice === null)
      return wifiNetworks;
    return [{
      "key": "ethernet:" + wiredDevice.name,
      "type": "ethernet",
      "label": wiredConnectionLabel,
      "ssid": "",
      "strength": 100,
      "security": "",
      "active": true,
      "known": true,
      "nativeNetwork": wiredDevice.network
    }].concat(wifiNetworks);
  }
  readonly property var activeWifiNetwork: wifiNetworks.find(network =>
    network.active) ?? null
  readonly property string type: wiredDevice !== null
    ? "ethernet" : activeWifiNetwork !== null ? "wifi"
      : !wifiEnabled ? "disabled" : "disconnected"
  readonly property int strength: wiredDevice !== null
    ? 100 : activeWifiNetwork !== null ? activeWifiNetwork.strength : 0

  onEntriesChanged: syncSelection()
  onWifiDeviceChanged: {
    stopScan();
    if (active) refresh(true);
  }

  function icon() {
    if (type === "ethernet")
      return "󰈀";
    if (type !== "wifi")
      return "󰤭";
    if (strength < 26)
      return "󰤟";
    if (strength < 51)
      return "󰤢";
    if (strength < 76)
      return "󰤥";
    return "󰤨";
  }

  onActiveChanged: {
    if (active) {
      selectedIndex = 0;
      selectedKey = entries.length > 0 ? entries[0].key : "";
      message = "";
      refresh(true);
    } else {
      cancelPassword();
      forgetConnection();
      cancelSpeedTest();
      stopScan();
    }
  }

  function forgetConnection() {
    connectionTimer.stop();
    pendingNetwork = null;
    connectionUsedPassword = false;
  }

  function cancelPassword() {
    passwordMode = false;
    password = "";
    message = "";
  }

  function appendPassword(text) {
    if (!active || !passwordMode) return;
    password += text;
    message = "";
  }

  function erasePassword() {
    password = password.slice(0, -1);
    message = "";
  }

  function syncSelection() {
    const previousKey = selectedKey;
    if (entries.length === 0) {
      forgetConnection();
      selectedIndex = 0;
      selectedKey = "";
      if (previousKey !== "" && passwordMode) {
        passwordMode = false;
        password = "";
        message = "Network no longer available";
      }
      return;
    }

    const preservedIndex = entries.findIndex(entry =>
      entry.key === previousKey);
    selectedIndex = preservedIndex >= 0 ? preservedIndex
      : Math.min(selectedIndex, entries.length - 1);
    selectedKey = entries[selectedIndex].key;
    if (pendingNetwork !== null && pendingNetwork.key !== selectedKey)
      forgetConnection();
    if (previousKey !== "" && preservedIndex < 0 && passwordMode) {
      passwordMode = false;
      password = "";
      message = "Network no longer available";
    }
  }

  function setSelection(index, direction) {
    if (entries.length === 0)
      return;
    selectionDirection = direction;
    selectedIndex = Math.max(0,
      Math.min(index, entries.length - 1));
    selectedKey = entries[selectedIndex].key;
    if (pendingNetwork !== null && pendingNetwork.key !== selectedKey)
      forgetConnection();
    passwordMode = false;
    password = "";
    message = "";
  }

  function moveSelection(delta) {
    if (entries.length === 0)
      return;
    setSelection((selectedIndex + delta + entries.length)
      % entries.length, delta >= 0 ? 1 : -1);
  }

  function finishRefresh() {
    // In Quickshell 0.3, disabling the scanner also hides every unknown,
    // disconnected network. Keep it enabled for the selector's lifetime and
    // stop only the temporary loading indicator here.
    loading = false;
  }

  function stopScan() {
    scanTimer.stop();
    if (startedScan && scanDevice !== null && scanDevice.scannerEnabled)
      scanDevice.scannerEnabled = false;
    scanDevice = null;
    startedScan = false;
    loading = false;
  }

  function refresh(silent = false) {
    if (!active) return;
    if (wifiDevice === null) {
      loading = false;
      if (!silent)
        message = "Wi-Fi device unavailable";
      return;
    }

    if (!silent) {
      loading = true;
      message = "";
    }

    // scannerEnabled drives NetworkManager scans continuously and also keeps
    // discovered networks exposed through wifiDevice.networks.
    if (!wifiDevice.scannerEnabled) {
      wifiDevice.scannerEnabled = true;
      startedScan = true;
    }
    scanDevice = wifiDevice;
    scanTimer.restart();
  }

  function resetSpeedTestValues() {
    speedTestHasResult = false;
    speedTestPing = "--";
    speedTestDownload = "--";
    speedTestUpload = "--";
    speedTestPhase = "";
    speedTestLiveValue = "";
    speedTestProgress = 0;
  }

  function startSpeedTest() {
    if (!active || speedTestRunning)
      return;

    speedTestExpanded = true;
    speedTestMessage = "";
    resetSpeedTestValues();
    if (type === "disabled" || type === "disconnected") {
      speedTestMessage = "No active connection";
      return;
    }

    const generation = ++speedTestGeneration;
    speedTestPhase = "STARTING";
    speedTestRunning = true;
    speedTestTimer.restart();
    // Each invocation owns its generation, including its deferred exit callback.
    speedTestProcess = speedTestJob.createObject(root, {generation: generation});
  }

  function cancelSpeedTest() {
    speedTestGeneration++;
    speedTestExpanded = false;
    speedTestRunning = false;
    speedTestMessage = "";
    speedTestTimer.stop();
    stopSpeedTestProcess();
    resetSpeedTestValues();
  }

  function failSpeedTest(message = "Speed test failed") {
    speedTestGeneration++;
    speedTestTimer.stop();
    speedTestRunning = false;
    stopSpeedTestProcess();
    speedTestMessage = message;
    resetSpeedTestValues();
  }

  function setSpeedTestProgress(phase, stageProgress, start, span,
      liveValue = "") {
    const parsedProgress = Number(stageProgress);
    const progress = Number.isFinite(parsedProgress)
      ? Math.max(0, Math.min(1, parsedProgress)) : 0;
    speedTestPhase = phase;
    speedTestProgress = start + progress * span;
    speedTestLiveValue = liveValue;
  }

  function parseSpeedTestEvent(text) {
    if (!active || !speedTestRunning) return;
    const responseText = text.trim();
    if (responseText === "")
      return;

    try {
      const response = JSON.parse(responseText);
      if (response?.generation === undefined
          || response.generation.toString() !== speedTestGeneration.toString())
        return;
      if (response.type === "error" || response.error !== undefined) {
        console.warn("Speed test failed:", response.error);
        failSpeedTest();
        return;
      }

      if (response.type === "testStart") {
        speedTestPhase = "PING";
        speedTestProgress = 0;
        speedTestLiveValue = "";
      } else if (response.type === "ping") {
        const latency = Number(response.ping?.latency);
        setSpeedTestProgress("PING", response.ping?.progress, 0, 0.15,
          Number.isFinite(latency) ? latency.toFixed(1) + " ms" : "");
      } else if (response.type === "download") {
        const speed = Number(response.download?.bandwidth) * 8 / 1000000;
        setSpeedTestProgress("DOWNLOAD", response.download?.progress,
          0.15, 0.45,
          Number.isFinite(speed) ? speed.toFixed(1) + " Mb/s" : "");
      } else if (response.type === "upload") {
        const speed = Number(response.upload?.bandwidth) * 8 / 1000000;
        setSpeedTestProgress("UPLOAD", response.upload?.progress,
          0.60, 0.35,
          Number.isFinite(speed) ? speed.toFixed(1) + " Mb/s" : "");
      } else if (response.type === "packetLoss") {
        speedTestPhase = "FINALIZING";
        speedTestProgress = 0.95;
        speedTestLiveValue = "";
      } else if (response.type === "result") {
        const ping = Number(response.ping?.latency);
        const download = Number(response.download?.bandwidth) * 8 / 1000000;
        const upload = Number(response.upload?.bandwidth) * 8 / 1000000;
        if (!Number.isFinite(ping) || !Number.isFinite(download)
            || !Number.isFinite(upload))
          throw new Error("Missing speed test metrics");

        speedTestTimer.stop();
        speedTestPing = ping.toFixed(1);
        speedTestDownload = download.toFixed(1);
        speedTestUpload = upload.toFixed(1);
        speedTestProgress = 1;
        speedTestHasResult = true;
        speedTestRunning = false;
        speedTestMessage = "";
      }
    } catch (error) {
      console.warn("Unable to parse speed test event:", error);
      failSpeedTest();
    }
  }

  function timeoutSpeedTest() {
    if (!speedTestRunning)
      return;
    failSpeedTest("Speed test timed out");
  }

  function stopSpeedTestProcess() {
    if (speedTestProcess !== null) {
      speedTestProcess.running = false;
      speedTestProcess = null;
    }
  }

  function isSecured(network) {
    return network.security !== "" && network.security !== "--"
      && network.security.toLowerCase() !== "open";
  }

  function connectSelected() {
    if (!active || entries.length === 0)
      return;
    const network = entries[Math.min(selectedIndex,
      entries.length - 1)];
    if (network.type === "ethernet" || network.active) {
      closeRequested();
      return;
    }
    if (pendingNetwork !== null)
      return;

    if (passwordMode && password.length === 0) {
      message = "Password required";
      return;
    }

    if (!passwordMode && isSecured(network) && !network.known) {
      passwordMode = true;
      password = "";
      message = "";
      return;
    }

    pendingNetwork = network;
    connectionUsedPassword = passwordMode;
    message = "Connecting to " + network.ssid + "…";
    connectionTimer.restart();

    if (passwordMode) {
      const secret = password;
      password = "";
      passwordMode = false;
      network.nativeNetwork.connectWithPsk(secret);
    } else {
      network.nativeNetwork.connect();
    }
  }

  function failConnection() {
    if (!active || pendingNetwork === null) return;
    connectionTimer.stop();
    const network = pendingNetwork;
    pendingNetwork = null;
    if (network !== null && isSecured(network)) {
      passwordMode = true;
      password = "";
      message = connectionUsedPassword
        ? "Incorrect password" : "Password required";
    } else {
      message = "Unable to connect";
    }
    connectionUsedPassword = false;
  }


  Connections {
    enabled: root.active
    target: root.pendingNetwork !== null
      ? root.pendingNetwork.nativeNetwork : null

    function onConnectedChanged() {
      if (root.active && root.pendingNetwork !== null
          && root.pendingNetwork.nativeNetwork.connected) {
        connectionTimer.stop();
        root.pendingNetwork = null;
        root.connectionUsedPassword = false;
        root.closeRequested();
      }
    }

    function onConnectionFailed(reason) {
      root.failConnection();
    }
  }

  Timer {
    id: scanTimer
    interval: 5000
    onTriggered: root.finishRefresh()
  }

  Timer {
    id: connectionTimer
    interval: 20000
    onTriggered: root.failConnection()
  }

  Timer {
    id: speedTestTimer
    interval: 90000
    onTriggered: root.timeoutSpeedTest()
  }

  Component {
    id: speedTestJob
    Process {
      id: job
      required property int generation
      command: root.speedTestCommand.concat([generation.toString()])
      running: true
      stdout: SplitParser {
        onRead: data => root.parseSpeedTestEvent(data)
      }
      onExited: (exitCode, exitStatus) => {
        Qt.callLater(() => {
          if (root.active && root.speedTestRunning
              && job.generation === root.speedTestGeneration)
            root.failSpeedTest();
          if (root.speedTestProcess === job)
            root.speedTestProcess = null;
          job.destroy();
        });
      }
    }
  }
  Component.onDestruction: {
    stopScan();
    password = "";
  }
}
