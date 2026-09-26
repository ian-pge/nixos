import Quickshell
import Quickshell.Bluetooth
import QtQuick

// Bluetooth discovery/actions have no knowledge of the shell or its surfaces.
Scope {
  id: root
  property bool active: false
  property var adapter: Bluetooth.defaultAdapter
  property var nativeDevices: Bluetooth.devices.values
  signal closeRequested()

  property int tab: 0
  property int selectedIndex: 0
  property string selectedAddress: ""
  property int selectionDirection: 1
  property bool loading: false
  property bool scanning: false
  property bool refreshSilent: false
  property string message: ""
  property string action: ""
  property var actionDevice: null
  property bool startedDiscovery: false
  property var discoveryAdapter: null
  readonly property var devices: nativeDevices.map(device => ({
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
  onDevicesChanged: {
    syncSelection();
    if (actionDevice !== null && !nativeDevices.includes(actionDevice)) {
      forgetAction();
      if (active) message = "Device no longer available";
    }
  }
  onAdapterChanged: stopDiscovery()
  readonly property bool connected: nativeDevices
    .some(device => device.connected)


  readonly property var currentDevices: filteredDevices()

  onActiveChanged: {
    if (active) {
      tab = 0;
      selectedIndex = 0;
      syncSelection("");
      message = "";
    } else {
      stopDiscovery();
      forgetAction();
      message = "";
    }
  }

  function forgetAction() {
    actionTimer.stop();
    actionDevice = null;
    action = "";
  }

  function filteredDevices() {
    return devices.filter(device => tab === 0
      ? device.paired : !device.paired);
  }

  function syncSelection(preferredAddress = selectedAddress) {
    const devices = filteredDevices();
    if (devices.length === 0) {
      selectedIndex = 0;
      selectedAddress = "";
      return;
    }
    const preservedIndex = devices.findIndex(device =>
      device.address === preferredAddress);
    selectedIndex = preservedIndex >= 0 ? preservedIndex
      : Math.min(selectedIndex, devices.length - 1);
    selectedAddress = devices[selectedIndex].address;
  }

  function moveSelection(delta) {
    const devices = filteredDevices();
    if (devices.length === 0)
      return;
    selectionDirection = delta >= 0 ? 1 : -1;
    selectedIndex = (selectedIndex + delta + devices.length)
      % devices.length;
    selectedAddress = devices[selectedIndex].address;
    message = "";
  }

  function stopDiscovery() {
    scanTimer.stop();
    if (startedDiscovery && discoveryAdapter !== null)
      discoveryAdapter.discovering = false;
    discoveryAdapter = null;
    startedDiscovery = false;
    loading = false;
    scanning = false;
    refreshSilent = false;
  }

  function switchTab() {
    if (!active) return;
    tab = tab === 0 ? 1 : 0;
    selectedIndex = 0;
    syncSelection("");
    message = "";
    if (tab === 1)
      refresh(true, false);
    else
      stopDiscovery();
  }

  function refresh(scan, silent = false) {
    if (!active || !scan)
      return;
    if (adapter === null) {
      if (!silent)
        message = "Bluetooth adapter unavailable";
      return;
    }

    refreshSilent = silent;
    if (!silent) {
      loading = true;
      scanning = true;
      message = "";
    }
    if (!adapter.discovering) {
      startedDiscovery = true;
      discoveryAdapter = adapter;
      adapter.discovering = true;
    }
    scanTimer.restart();
  }

  function activateSelected() {
    if (!active || actionDevice !== null)
      return;
    const devices = filteredDevices();
    if (devices.length === 0)
      return;
    const device = devices[Math.min(selectedIndex, devices.length - 1)];
    const nativeDevice = device.nativeDevice;
    selectedAddress = device.address;
    action = tab === 1
      ? "pair" : nativeDevice.connected ? "disconnect" : "connect";
    actionDevice = nativeDevice;
    message = action === "pair"
      ? "Pairing with " + device.name + "…"
      : action === "connect"
        ? "Connecting to " + device.name + "…"
        : "Disconnecting " + device.name + "…";
    actionTimer.restart();

    if (action === "pair")
      nativeDevice.pair();
    else if (action === "connect")
      nativeDevice.connect();
    else
      nativeDevice.disconnect();
  }

  function finishAction(succeeded) {
    if (!active || actionDevice === null) return;
    actionTimer.stop();
    const completedDeviceAddress = actionDevice !== null
      ? actionDevice.address : selectedAddress;
    if (succeeded) {
      if (action === "pair") {
        if (actionDevice !== null)
          actionDevice.trusted = true;
        tab = 0;
        selectedIndex = 0;
        syncSelection(completedDeviceAddress);
        stopDiscovery();
      }
      message = "";
    } else {
      message = "Bluetooth action failed";
    }
    actionDevice = null;
    action = "";
  }

  Connections {
    target: root.actionDevice
    enabled: root.active

    function onConnectedChanged() {
      if (!root.active || root.actionDevice === null)
        return;
      if (root.action === "connect" && root.actionDevice.connected)
        root.finishAction(true);
      else if (root.action === "disconnect"
          && !root.actionDevice.connected)
        root.finishAction(true);
    }

    function onPairedChanged() {
      if (root.active && root.action === "pair" && root.actionDevice !== null
          && root.actionDevice.paired)
        root.finishAction(true);
    }
  }

  Timer {
    id: scanTimer
    interval: 5000
    onTriggered: root.stopDiscovery()
  }

  Timer {
    id: actionTimer
    interval: 20000
    onTriggered: root.finishAction(false)
  }
  Component.onDestruction: stopDiscovery()
}
