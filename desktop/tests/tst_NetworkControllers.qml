import QtQuick
import QtTest
import Quickshell
import Quickshell.Networking

// All native devices and subprocesses are injected. No real scans/connections.
ShellRoot {
  id: fixture
  property bool ready: false
  property var network: null
  property var bluetooth: null
  property var wifiView: null
  property var bluetoothView: null
  property var events: []
  property var transientObjects: []

  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        || !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
      Qt.callLater(() => Qt.exit(1));
      return;
    }
    const directory = "file://" + Quickshell.shellDir + "/../features/network/";
    function create(file, parent, properties) {
      const component = Qt.createComponent(directory + file + ".qml");
      if (component.status !== Component.Ready) {
        console.error(component.errorString());
        Qt.callLater(() => Qt.exit(1));
        return null;
      }
      return component.createObject(parent, properties);
    }
    network = create("NetworkController", fixture, {
      devices: [], wifiEnabled: true,
      speedTestCommand: ["sh", "-c", "sleep 0.1"]
    });
    bluetooth = create("BluetoothController", fixture, {adapter: adapterMock, nativeDevices: []});
    if (network === null || bluetooth === null) return;
    network.closeRequested.connect(() => fixture.events.push("close-network"));
    bluetooth.closeRequested.connect(() => fixture.events.push("close-bluetooth"));
    wifiView = create("WifiSelector", window.contentItem, {
      controller: network, width: 400, height: 94, enabled: false, visible: false
    });
    bluetoothView = create("BluetoothSelector", window.contentItem, {
      controller: bluetooth, width: 400, height: 36, enabled: false, visible: false
    });
    if (wifiView === null || bluetoothView === null) return;
    wifiView.closeRequested.connect(() => fixture.events.push("close-wifi-view"));
    bluetoothView.closeRequested.connect(() => fixture.events.push("close-bluetooth-view"));
    ready = true;
  }

  Window { id: window; width: 420; height: 100; visible: true }
  QtObject { id: adapterMock; property bool discovering: false }
  QtObject { id: replacementAdapter; property bool discovering: false }
  QtObject {
    id: wifiDeviceMock
    property int type: DeviceType.Wifi
    property bool scannerEnabled: false
    property QtObject networks: QtObject { property var values: [] }
  }
  QtObject {
    id: ethernetMock
    property int type: DeviceType.Wired
    property string name: "Ethernet"
    property bool connected: true
    property var network: null
  }
  Component {
    id: wifiNetworkMock
    QtObject {
      property string name: ""
      property real signalStrength: 0.5
      property int security: WifiSecurityType.Wpa2Psk
      property bool connected: false
      property bool known: false
      signal connectionFailed(string reason)
      function connect() { fixture.events.push("wifi-connect:" + name); }
      function connectWithPsk(secret) {
        fixture.events.push("wifi-password:" + name + ":" + secret);
      }
    }
  }
  Component {
    id: bluetoothDeviceMock
    QtObject {
      property string address: ""
      property string name: ""
      property string deviceName: ""
      property bool connected: false
      property bool paired: true
      property bool trusted: false
      function connect() { fixture.events.push("bt-connect:" + address); }
      function disconnect() { fixture.events.push("bt-disconnect:" + address); }
      function pair() { fixture.events.push("bt-pair:" + address); }
    }
  }

  TestResult { id: results }
  TestCase {
    name: "NetworkControllers"
    when: fixture.ready
    function cleanupTestCase() {
      console.log("NetworkControllers: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      network.active = false;
      bluetooth.active = false;
      network.devices = [];
      wifiDeviceMock.networks.values = [];
      bluetooth.nativeDevices = [];
      for (const object of fixture.transientObjects) object.destroy();
      fixture.transientObjects = [];
      wifiView.enabled = false; wifiView.visible = false;
      bluetoothView.enabled = false; bluetoothView.visible = false;
      wait(1);
    }
    function init() {
      fixture.events = [];
      network.wifiEnabled = true;
      network.speedTestCommand = ["sh", "-c", "sleep 0.1"];
      network.devices = [wifiDeviceMock];
      network.active = true;
      bluetooth.adapter = adapterMock;
      adapterMock.discovering = false;
      replacementAdapter.discovering = false;
      bluetooth.active = true;
    }
    function wifi(name, overrides = {}) {
      const object = wifiNetworkMock.createObject(fixture, Object.assign({name: name}, overrides));
      fixture.transientObjects.push(object);
      return object;
    }
    function bt(name, overrides = {}) {
      const object = bluetoothDeviceMock.createObject(fixture,
        Object.assign({name: name, address: name}, overrides));
      fixture.transientObjects.push(object);
      return object;
    }
    function speedResult(generation) {
      return JSON.stringify({generation: generation, type: "result", ping: {latency: 12.34},
        download: {bandwidth: 12500000}, upload: {bandwidth: 1250000}});
    }
    function test_wifi_scan_lifecycle_and_device_replacement() {
      verify(wifiDeviceMock.scannerEnabled);
      network.refresh();
      verify(network.loading);
      network.finishRefresh();
      verify(!network.loading);
      verify(wifiDeviceMock.scannerEnabled);
      network.devices = [];
      verify(!wifiDeviceMock.scannerEnabled);
      network.devices = [wifiDeviceMock];
      verify(wifiDeviceMock.scannerEnabled);
      network.active = false;
      verify(!wifiDeviceMock.scannerEnabled);
      network.refresh();
      verify(!wifiDeviceMock.scannerEnabled);
    }
    function test_network_status_and_ethernet_priority() {
      const first = wifi("Office", {connected: true, signalStrength: 0.72});
      wifiDeviceMock.networks.values = [first];
      compare(network.type, "wifi");
      compare(network.strength, 72);
      network.devices = [wifiDeviceMock, ethernetMock];
      compare(network.type, "ethernet");
      compare(network.entries[0].key, "ethernet:Ethernet");
      network.setSelection(0, 1); network.connectSelected();
      compare(fixture.events.join(","), "close-network");
      network.devices = []; network.wifiEnabled = false;
      compare(network.type, "disabled");
    }
    function test_wifi_external_scan_is_not_stopped() {
      network.active = false;
      wifiDeviceMock.scannerEnabled = true;
      network.active = true;
      network.active = false;
      verify(wifiDeviceMock.scannerEnabled);
      wifiDeviceMock.scannerEnabled = false;
    }
    function test_wifi_selection_preserved_across_signal_sorting() {
      const one = wifi("One", {signalStrength: 0.8});
      const two = wifi("Two", {signalStrength: 0.2});
      wifiDeviceMock.networks.values = [one, two];
      network.setSelection(1, 1);
      compare(network.selectedKey, "wifi:Two");
      two.signalStrength = 0.9;
      compare(network.selectedIndex, 0);
      compare(network.selectedKey, "wifi:Two");
      network.moveSelection(-1);
      compare(network.selectedKey, "wifi:One");
    }
    function test_password_prompt_cleared_when_network_disappears() {
      const one = wifi("One");
      const two = wifi("Two");
      wifiDeviceMock.networks.values = [one, two];
      network.connectSelected(); network.appendPassword("temporary-secret");
      verify(network.passwordMode);
      wifiDeviceMock.networks.values = [two];
      compare(network.password, "");
      verify(!network.passwordMode);
      compare(network.message, "Network no longer available");
      compare(fixture.events.length, 0);
    }
    function test_password_submit_clears_secret_and_success_requests_close() {
      const one = wifi("One");
      wifiDeviceMock.networks.values = [one];
      network.connectSelected(); network.connectSelected();
      compare(network.message, "Password required");
      network.appendPassword("secret"); network.connectSelected();
      compare(network.password, ""); verify(!network.passwordMode);
      compare(fixture.events.join(","), "wifi-password:One:secret");
      one.connected = true;
      compare(fixture.events.join(","), "wifi-password:One:secret,close-network");
      compare(network.pendingNetwork, null);
    }
    function test_late_wifi_response_does_not_close_new_selection() {
      const one = wifi("One", {known: true});
      const two = wifi("Two", {known: true});
      wifiDeviceMock.networks.values = [one, two];
      network.connectSelected(); network.moveSelection(1);
      one.connectionFailed("old failure"); one.connected = true;
      verify(!network.passwordMode);
      compare(fixture.events.join(","), "wifi-connect:One");
      network.active = false;
      network.failConnection();
      compare(network.message, "");
      compare(network.password, "");
    }
    function test_open_wifi_and_hidden_controller_do_not_prompt_or_connect() {
      const open = wifi("Public", {security: WifiSecurityType.Open});
      wifiDeviceMock.networks.values = [open];
      network.connectSelected();
      verify(!network.passwordMode);
      compare(fixture.events.join(","), "wifi-connect:Public");
      network.active = false;
      open.connected = true;
      network.connectSelected();
      compare(fixture.events.join(","), "wifi-connect:Public");
    }
    function test_connection_failure_returns_to_password_without_retaining_it() {
      const one = wifi("One"); wifiDeviceMock.networks.values = [one];
      network.connectSelected(); network.appendPassword("wrong"); network.connectSelected();
      one.connectionFailed("bad credentials");
      verify(network.passwordMode);
      compare(network.password, "");
      compare(network.message, "Incorrect password");
      network.active = false;
      verify(!network.passwordMode);
    }
    function test_speedtest_generations_and_metrics() {
      network.devices = [ethernetMock];
      network.startSpeedTest();
      const oldGeneration = network.speedTestGeneration;
      network.cancelSpeedTest(); network.startSpeedTest();
      const generation = network.speedTestGeneration;
      network.parseSpeedTestEvent(speedResult(oldGeneration));
      verify(network.speedTestRunning);
      network.parseSpeedTestEvent(JSON.stringify({generation: generation, type: "download",
        download: {progress: 0.5, bandwidth: 12500000}}));
      compare(network.speedTestPhase, "DOWNLOAD");
      compare(network.speedTestLiveValue, "100.0 Mb/s");
      fuzzyCompare(network.speedTestProgress, 0.375, 0.001);
      network.parseSpeedTestEvent(speedResult(generation));
      verify(network.speedTestHasResult);
      compare(network.speedTestPing, "12.3");
      compare(network.speedTestDownload, "100.0");
      compare(network.speedTestUpload, "10.0");
      network.parseSpeedTestEvent(JSON.stringify({generation: generation, type: "error"}));
      verify(network.speedTestHasResult);
    }
    function test_speedtest_timeout_and_close_ignore_late_results() {
      network.devices = [ethernetMock]; network.startSpeedTest();
      const generation = network.speedTestGeneration;
      network.timeoutSpeedTest();
      compare(network.speedTestMessage, "Speed test timed out");
      network.parseSpeedTestEvent(speedResult(generation));
      verify(!network.speedTestHasResult);
      network.startSpeedTest(); network.active = false;
      network.parseSpeedTestEvent(speedResult(network.speedTestGeneration));
      verify(!network.speedTestRunning); verify(!network.speedTestExpanded);
    }
    function test_speedtest_subprocess_exit_and_inactive_launch_guard() {
      network.devices = [ethernetMock]; network.startSpeedTest();
      tryCompare(network, "speedTestRunning", false, 2000);
      compare(network.speedTestMessage, "Speed test failed");
      network.active = false; network.startSpeedTest();
      verify(!network.speedTestRunning);
    }
    function test_canceled_subprocess_exit_cannot_fail_new_speedtest() {
      network.devices = [ethernetMock];
      network.speedTestCommand = ["sh", "-c", "exit 0"];
      network.startSpeedTest();
      network.cancelSpeedTest();
      network.speedTestCommand = ["sh", "-c", "sleep 0.1"];
      network.startSpeedTest();
      wait(20);
      verify(network.speedTestRunning);
      compare(network.speedTestMessage, "");
      network.parseSpeedTestEvent(speedResult(network.speedTestGeneration));
      verify(network.speedTestHasResult);
    }
    function test_bluetooth_tab_scan_and_selection() {
      const one = bt("One"); const two = bt("Two"); const nearby = bt("Nearby", {paired: false});
      bluetooth.nativeDevices = [one, two, nearby];
      bluetooth.moveSelection(1);
      compare(bluetooth.selectedAddress, "Two");
      two.connected = true;
      compare(bluetooth.selectedAddress, "Two"); compare(bluetooth.selectedIndex, 0);
      bluetooth.switchTab();
      compare(bluetooth.currentDevices.length, 1);
      compare(bluetooth.selectedAddress, "Nearby");
      verify(adapterMock.discovering);
      bluetooth.switchTab();
      verify(!adapterMock.discovering);
    }
    function test_bluetooth_discovery_ownership_and_adapter_replacement() {
      adapterMock.discovering = true;
      bluetooth.refresh(true); bluetooth.active = false;
      verify(adapterMock.discovering); // Someone else's scan is not ours to stop.
      adapterMock.discovering = false; bluetooth.active = true;
      bluetooth.refresh(true); bluetooth.adapter = replacementAdapter;
      verify(!adapterMock.discovering);
      bluetooth.refresh(true); bluetooth.active = false;
      verify(!replacementAdapter.discovering);
    }
    function test_bluetooth_pair_completion_and_device_loss() {
      const device = bt("Nearby", {paired: false}); bluetooth.nativeDevices = [device];
      bluetooth.switchTab(); bluetooth.activateSelected();
      compare(fixture.events.join(","), "bt-pair:Nearby");
      device.paired = true;
      verify(device.trusted);
      compare(bluetooth.tab, 0);
      compare(bluetooth.selectedAddress, "Nearby");
      verify(!adapterMock.discovering);
      bluetooth.activateSelected();
      bluetooth.nativeDevices = [];
      compare(bluetooth.actionDevice, null);
      compare(bluetooth.message, "Device no longer available");
    }
    function test_bluetooth_connect_disconnect_and_late_action() {
      const device = bt("Paired"); bluetooth.nativeDevices = [device];
      bluetooth.activateSelected(); device.connected = true;
      compare(bluetooth.actionDevice, null);
      verify(bluetooth.connected);
      bluetooth.activateSelected();
      compare(fixture.events.join(","), "bt-connect:Paired,bt-disconnect:Paired");
      bluetooth.active = false; device.connected = false;
      bluetooth.finishAction(false);
      compare(bluetooth.message, "");
      compare(bluetooth.action, "");
    }
    function test_bluetooth_late_pairing_after_close_does_not_change_new_panel() {
      const device = bt("Nearby", {paired: false}); bluetooth.nativeDevices = [device];
      bluetooth.switchTab(); bluetooth.activateSelected();
      bluetooth.active = false; bluetooth.active = true;
      bluetooth.switchTab();
      device.paired = true;
      compare(bluetooth.tab, 1);
      verify(!device.trusted);
      compare(bluetooth.actionDevice, null);
    }
    function test_views_keep_keyboard_navigation_and_close_contract() {
      wifiDeviceMock.networks.values = [wifi("One"), wifi("Two")];
      wifiView.visible = true; wifiView.enabled = true;
      wifiView.forceActiveFocus(); wait(10);
      keyClick(Qt.Key_J); compare(network.selectedKey, "wifi:Two");
      keyClick(Qt.Key_Return); verify(network.passwordMode);
      keyClick(Qt.Key_Escape); verify(!network.passwordMode);
      keyClick(Qt.Key_Escape);
      compare(fixture.events.join(","), "close-wifi-view");
      wifiView.enabled = false; wifiView.visible = false;
      bluetooth.nativeDevices = [bt("Paired"), bt("Nearby", {paired: false})];
      bluetoothView.visible = true; bluetoothView.enabled = true;
      bluetoothView.forceActiveFocus(); wait(10);
      keyClick(Qt.Key_Tab); compare(bluetooth.tab, 1);
      keyClick(Qt.Key_Escape);
      compare(fixture.events.join(","), "close-wifi-view,close-bluetooth-view");
    }
  }
}
