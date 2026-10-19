import QtQuick
import QtTest
import Quickshell
import Quickshell.Services.UPower

// Providers are injected and helpers disabled: no real device/network/mic actions.
ShellRoot {
  id: fixture
  property var brightness: null
  property var dictation: null
  property var calendar: null
  property var system: null
  property var media: null
  property var power: null
  property var feedback: []
  property var mediaActions: []
  property int sampledBrightness: -1
  QtObject { id: fakeWeather; property bool autoRefresh: false }
  QtObject {
    id: executor
    property bool running: false
    property var calls: []
    function exec(command) { calls = calls.concat([command]); running = true; }
  }
  QtObject { id: telemetry; property bool systemFresh: true; property var usbDevices: []; property var hidppBatteries: [] }
  function create(name, properties) {
    const c = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/" + name + ".qml");
    if (c.status !== Component.Ready) { console.error(c.errorString()); Qt.exit(1); return null; }
    return c.createObject(fixture, properties);
  }
  Component.onCompleted: {
    brightness = create("brightness/BrightnessController", {enabled: false, executor: executor});
    dictation = create("dictation/DictationController", {enabled: false});
    calendar = create("calendar/CalendarController", {enabled: false, weather: fakeWeather});
    system = create("system/SystemController", {enabled: false});
    media = create("audio/MediaController", {enabled: false});
    power = create("power/PowerController", {enabled: false, telemetry: telemetry});
    brightness.feedbackRequested.connect(monitor => feedback = feedback.concat([monitor]));
    media.feedbackRequested.connect(monitor => feedback = feedback.concat([monitor]));
    system.brightnessSample.connect(value => sampledBrightness = value);
  }
  TestResult { id: results }
  TestCase {
    name: "FeatureControllers"
    when: fixture.power !== null
    function cleanupTestCase() {
      console.log("FeatureControllers: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function init() {
      brightness.enabled = false; brightness.monitors = []; brightness.reset(); brightness.sample = 30;
      executor.running = false; executor.calls = [];
      dictation.setState("stopped"); dictation.audioConnected = false; dictation.resetAudio();
      system.topRequested = false; system.telemetry.invalidateSystem(); system.telemetry.invalidateGpu();
      media.players = []; feedback = []; mediaActions = []; sampledBrightness = -1;
      power.battery = null; power.onBattery = true; power.powerDevices = []; power.bluetoothDevices = [];
      power.phoneRelay.invalidate(); power.phoneRelay.now = Date.now(); power.phoneName = "Pixel 8 Pro";
      telemetry.systemFresh = true; telemetry.usbDevices = []; telemetry.hidppBatteries = [];
    }
    function test_brightness_values_belong_to_each_monitor() {
      compare(brightness.value("eDP-1"), 30);
      compare(brightness.value("DP-1"), null);
      compare(brightness.value("HDMI-A-1"), null);
      compare(brightness.value(""), null);
      brightness.requestGeneration = brightness.generation;
      brightness.parseStatus('{"monitor":"DP-1","brightness":80}');
      brightness.parseStatus('{"monitor":"HDMI-A-1","brightness":0}');
      brightness.sample = 45;
      compare(brightness.value("eDP-1"), 45);
      compare(brightness.value("DP-1"), 80);
      compare(brightness.value("HDMI-A-1"), 0);
      brightness.requestMonitor = "DP-1"; brightness.fail();
      compare(brightness.value("DP-1"), null, "An unavailable display never uses the laptop's reading");
    }
    function test_brightness_startup_reads_all_monitors_without_osd_or_writes() {
      brightness.monitors = ["eDP-1", "DP-1", "HDMI-A-1"];
      brightness.refreshMonitors();
      compare(executor.calls.length, 0);
      compare(brightness.pendingChanges.length, 0);
      brightness.enabled = true;
      compare(executor.calls[0], ["quickshell-brightness", "eDP-1", "[0]", "null"]);
      brightness.refreshMonitors(); // A deferred startup callback must not duplicate requests.
      compare(brightness.pendingChanges.length, 2);
      for (const monitor of brightness.monitors) {
        compare(brightness.requestMonitor, monitor);
        brightness.parseStatus(JSON.stringify({monitor: monitor, brightness: 65}));
        executor.running = false; brightness.dispatch();
      }
      compare(executor.calls.length, 3);
      for (const command of executor.calls) compare(command[2], "[0]");
      brightness.refreshMonitors(); compare(executor.calls.length, 3);
      compare(feedback, []);
      compare(brightness.value("DP-1"), 65);
      compare(brightness.value("HDMI-A-1"), 65);
    }
    function test_brightness_hotplug_reads_new_topology_and_discards_old_result() {
      brightness.monitors = ["DP-1"];
      brightness.enabled = true;
      compare(executor.calls.length, 1);
      brightness.monitors = ["eDP-1", "DP-2"];
      brightness.refreshMonitors();
      brightness.parseStatus('{"monitor":"DP-1","brightness":80}');
      compare(brightness.value("DP-1"), null);
      compare(brightness.pendingChanges.map(change => change.monitor), ["eDP-1", "DP-2"]);
      executor.running = false; brightness.dispatch();
      compare(executor.calls[1], ["quickshell-brightness", "eDP-1", "[0]", "null"]);
      brightness.parseStatus('{"monitor":"eDP-1","brightness":30}');
      executor.running = false; brightness.dispatch();
      compare(executor.calls[2], ["quickshell-brightness", "DP-2", "[0]", "null"]);
      brightness.parseStatus('{"monitor":"DP-2","brightness":90}');
      compare(brightness.value("DP-2"), 90);
      compare(feedback, []);
    }
    function test_brightness_telemetry_updates_internal_panel_after_a_helper_read() {
      brightness.values = {"eDP-1": 50, "DP-1": 80};
      brightness.sample = 40;
      compare(brightness.value("eDP-1"), 40);
      compare(brightness.value("DP-1"), 80);
      brightness.values = {"eDP-1": 50, "DP-1": 80};
      brightness.change(5, "eDP-1");
      brightness.sample = 45;
      compare(brightness.value("eDP-1"), 55, "Telemetry must not erase a queued adjustment");
      brightness.enabled = true;
      brightness.sample = 50;
      compare(brightness.value("eDP-1"), 55, "Telemetry must not erase an in-flight adjustment");
      brightness.parseStatus('{"monitor":"eDP-1","brightness":55}');
      executor.running = false;
      brightness.sample = 55;
      compare(brightness.value("eDP-1"), 55);
      brightness.sample = 60;
      compare(brightness.value("eDP-1"), 60);
      compare(brightness.value("DP-1"), 80);
    }
    function test_brightness_change_during_initial_read_is_preserved() {
      brightness.monitors = ["DP-1"];
      brightness.enabled = true;
      brightness.change(5, "DP-1");
      brightness.parseStatus('{"monitor":"DP-1","brightness":70}');
      compare(brightness.value("DP-1"), 75);
      executor.running = false; brightness.dispatch();
      tryCompare(executor, "running", true, 1000);
      compare(executor.calls.length, 2);
      compare(executor.calls[1][2], "[5]");
      compare(feedback, ["DP-1"]);
    }
    function test_brightness_queue_preserves_clamped_direction_reversals() {
      brightness.values = {"DP-1": 95};
      brightness.change(10, "DP-1"); brightness.change(-10, "DP-1");
      compare(brightness.value("DP-1"), 90);
      compare(brightness.pendingChanges.length, 1);
      compare(brightness.pendingChanges[0].steps, [10, -10]);
      compare(feedback, ["DP-1", "DP-1"]);
      compare(executor.calls.length, 0);
      brightness.requestGeneration = brightness.generation;
      brightness.parseStatus(JSON.stringify({monitor: "DP-1", brightness: 95}));
      compare(brightness.value("DP-1"), 90, "A completed sample must include newer queued keypresses");
    }
    function test_brightness_reset_rejects_stale_status_and_failures() {
      brightness.requestGeneration = brightness.generation;
      brightness.reset();
      brightness.parseStatus('{"monitor":"DP-1","brightness":88}');
      compare(brightness.values, ({}));
      brightness.values = {"DP-1": 50}; brightness.requestMonitor = "DP-1";
      brightness.fail(); compare(brightness.values["DP-1"], 50);
      brightness.requestGeneration = brightness.generation;
      brightness.fail(); compare(brightness.values["DP-1"], undefined);
    }
    function test_brightness_injected_executor_gets_exact_helper_arguments() {
      brightness.enabled = true;
      brightness.states = {"eDP-1": {monitor: "eDP-1", brightness: 50}};
      brightness.change(5, "eDP-1");
      compare(executor.calls.length, 1);
      compare(executor.calls[0], ["quickshell-brightness", "eDP-1", "[5]", '{"monitor":"eDP-1","brightness":50}']);
      brightness.change(-5, "eDP-1"); compare(executor.calls.length, 1);
      executor.running = false; brightness.dispatch();
      compare(executor.calls.length, 2); compare(executor.calls[1][2], "[-5]");
      brightness.enabled = false;
    }
    function test_brightness_external_key_burst_is_coalesced() {
      brightness.enabled = true;
      brightness.change(5, "DP-1"); brightness.change(5, "DP-1");
      compare(executor.calls.length, 0);
      tryCompare(executor, "running", true, 1000);
      compare(executor.calls.length, 1); compare(executor.calls[0][2], "[5,5]");
      brightness.enabled = false;
    }
    function test_dictation_audio_is_bounded_and_cleared_on_transcription() {
      dictation.parseStatus('{"alt":"recording"}'); verify(dictation.active); verify(dictation.recording);
      dictation.parseAudio('{"peak":2,"rms":0.2,"vad":1}');
      compare(dictation.energy, 1); verify(dictation.speechDetected); verify(dictation.audioConnected);
      dictation.parseStatus('{"class":"transcribing"}');
      verify(dictation.active); verify(dictation.transcribing); verify(!dictation.recording);
      compare(dictation.energy, 0); verify(!dictation.speechDetected);
      dictation.parseAudio('{"peak":0.9,"rms":0.8,"vad":1}'); compare(dictation.energy, 0);
      dictation.setState("unknown"); verify(!dictation.active); compare(dictation.state, "stopped");
    }
    function test_dictation_disconnect_clears_signal_and_can_reconnect() {
      dictation.setState("streaming");
      dictation.parseAudio('{"peak":0.2,"rms":0.4,"vad":0}'); compare(dictation.energy, 0.4);
      dictation.parseAudio('{"status":"disconnected"}');
      verify(!dictation.audioConnected); compare(dictation.energy, 0);
      dictation.parseAudio('{"status":"connected"}'); verify(dictation.audioConnected);
      dictation.parseAudio('{"peak":"bad","rms":1}'); compare(dictation.energy, 0);
    }
    function test_calendar_today_following_does_not_override_user_navigation() {
      calendar.today = new Date(2026, 8, 10, 12); calendar.goToday();
      compare(calendar.selectedDate, "2026-09-10");
      calendar.today = new Date(2026, 8, 11, 12); compare(calendar.selectedDate, "2026-09-11");
      calendar.selectDate("2024-01-31", true); calendar.moveMonth(1);
      compare(calendar.selectedDate, "2024-02-29"); verify(!calendar.detailsOpen);
      calendar.today = new Date(2026, 8, 12, 12); compare(calendar.selectedDate, "2024-02-29");
      compare(calendar.weather, fakeWeather); verify(!fakeWeather.autoRefresh);
    }
    function test_system_samples_and_top_subscription_generation() {
      system.topRequested = true;
      const generation = system.telemetry.topRequestId; verify(generation > 0);
      system.acceptSystem(JSON.stringify({cpu: 12, memory: 34, disk: 56, brightness: 78,
        usbDevices: [{vendorId: "1234"}], top: {generation: generation, cpu: [], memory: []}}));
      compare(system.cpuUsage, 12); compare(system.memoryUsage, 34); compare(system.diskUsage, 56);
      compare(sampledBrightness, 78); verify(system.telemetry.systemFresh);
      compare(system.usbDevices.length, 1); verify(system.telemetry.processTopFresh);
      system.topRequested = false; verify(!system.telemetry.processTopFresh);
      system.topRequested = true;
      system.acceptSystem(JSON.stringify({cpu: 1, memory: 2, top: {generation: generation, cpu: [], memory: []}}));
      verify(!system.telemetry.processTopFresh, "A reopened panel must reject old collector generations");
    }
    function test_invalid_system_sample_clears_usb_power_evidence() {
      system.acceptSystem('{"cpu":12,"memory":25,"usbDevices":[{"vendorId":"1234"}]}');
      compare(system.usbDevices.length, 1);
      system.acceptSystem('{"error":"collector unavailable"}');
      verify(!system.telemetry.systemFresh); compare(system.usbDevices.length, 0);
      system.acceptGpu('{"text":"Sleeping","gpu":{"poweredOn":false}}');
      compare(system.gpuText, "Sleeping"); verify(system.telemetry.gpuFresh);
    }
    function fakePlayer(name, playing) {
      return {dbusName: name, canControl: true, isPlaying: playing, playbackState: 0,
        trackTitle: "Song", trackArtist: "Artist", identity: "Player",
        canTogglePlaying: true, canGoNext: true, canGoPrevious: true,
        togglePlaying: () => mediaActions = mediaActions.concat(["toggle"]),
        next: () => mediaActions = mediaActions.concat(["next"]),
        previous: () => mediaActions = mediaActions.concat(["previous"])};
    }
    function test_media_selection_and_only_explicit_action_feedback() {
      media.players = [fakePlayer("paused", false), fakePlayer("playing", true)];
      compare(media.player.dbusName, "playing"); compare(feedback.length, 0);
      media.players = media.players.concat([fakePlayer("org.mpris.playerctld", false)]);
      compare(media.player.dbusName, "org.mpris.playerctld"); compare(feedback.length, 0);
      compare(media.labelText, "Song  •  Artist");
      media.playPause("DP-1"); media.next("DP-1"); media.previous("DP-1");
      compare(mediaActions, ["toggle", "next", "previous"]); compare(feedback, ["DP-1", "DP-1", "DP-1"]);
      media.players = []; media.next(); compare(feedback.length, 3);
    }
    function test_power_uses_injected_battery_and_charging_devices() {
      power.battery = {ready: true, isPresent: true, percentage: 0.73}; power.onBattery = false;
      verify(power.batteryAvailable); verify(power.batteryPluggedIn); compare(power.batteryPercent, 73);
      power.bluetoothDevices = [{icon: "input-keyboard", address: "A", dbusPath: "/A", connected: true,
        batteryAvailable: true, battery: 0.45}];
      power.powerDevices = [{ready: true, isPresent: true, nativePath: "/A", state: UPowerDeviceState.Charging}];
      compare(power.keyboardBatteries.length, 1); compare(power.keyboardBatteries[0].percent, 45);
      verify(power.keyboardBatteries[0].pluggedIn);
    }
    function test_power_unplugging_clears_charging_before_global_state_catches_up() {
      power.onBattery = false;
      power.battery = {ready: true, isPresent: true, percentage: 0.73, state: UPowerDeviceState.Charging};
      verify(power.batteryPluggedIn);
      for (const state of [UPowerDeviceState.Discharging, UPowerDeviceState.PendingDischarge]) {
        power.battery = {ready: true, isPresent: true, percentage: 0.73, state: state};
        verify(!power.batteryPluggedIn);
      }
      for (const state of [UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge]) {
        power.battery = {ready: true, isPresent: true, percentage: 0.8, state: state};
        verify(power.batteryPluggedIn, "A full or charge-limited battery can still be plugged in");
      }
      power.onBattery = true;
      verify(!power.batteryPluggedIn);
    }
    function test_laptop_unknown_level_stays_visible_without_inventing_zero() {
      for (const level of [null, undefined, NaN, Infinity, -1, 1.01, "0.5"]) {
        power.battery = {ready: true, isPresent: true, percentage: level};
        verify(power.batteryAvailable); compare(power.batteryPercent, null);
        compare(power.batteries.length, 1); compare(power.batteries[0].percent, null);
      }
      power.battery = {ready: false, isPresent: true, percentage: 0.8}; power.onBattery = false;
      verify(power.batteryAvailable); compare(power.batteryPercent, null); verify(!power.batteryPluggedIn);
      power.battery = {ready: true, isPresent: true, percentage: 0}; power.onBattery = true;
      compare(power.batteryPercent, 0);
      power.battery = {ready: true, isPresent: false, percentage: 1};
      verify(!power.batteryAvailable); compare(power.batteries.length, 0);
    }
    function test_all_sources_keep_connected_devices_with_unknown_levels() {
      power.battery = {ready: true, isPresent: true, percentage: null};
      power.bluetoothDevices = [
        {icon: "input-keyboard", address: "KEYBOARD", connected: true, batteryAvailable: false},
        {icon: "input-mouse", address: "MOUSE", connected: true, batteryAvailable: false},
        {name: "Pixel Buds", address: "BUDS", connected: true, batteryAvailable: false}
      ];
      verify(phoneSample(null, null, null));
      compare(power.batteries.length, 5);
      for (const reading of power.batteries) {
        verify(reading.available); compare(reading.percent, null); verify(reading.pluggedIn !== true);
      }
      power.bluetoothDevices = power.bluetoothDevices.map(device => Object.assign({}, device, {connected: false}));
      power.phoneRelay.invalidate();
      compare(power.accessoryBatteries.length, 0);
      compare(power.batteries.length, 1, "The integrated battery stays visible");
    }
    function test_keyboard_unknown_percentage_and_power_are_independent() {
      const keyboard = {icon: "input-keyboard", address: "KEYBOARD", dbusPath: "/keyboard", connected: true, batteryAvailable: true};
      for (const level of [null, undefined, NaN, Infinity, -1, 1.01, "0.5"]) {
        power.bluetoothDevices = [Object.assign({}, keyboard, {battery: level})];
        compare(power.keyboardBatteries.length, 1); compare(power.keyboardBatteries[0].percent, null);
        compare(power.keyboardBatteries[0].pluggedIn, null);
      }
      power.bluetoothDevices = [Object.assign({}, keyboard, {battery: 0})];
      compare(power.keyboardBatteries[0].percent, 0);
      power.powerDevices = [{ready: true, isPresent: true, nativePath: "/keyboard", state: UPowerDeviceState.Charging}];
      verify(power.keyboardBatteries[0].pluggedIn);
      power.bluetoothDevices = [Object.assign({}, keyboard, {connected: false})];
      compare(power.keyboardBatteries.length, 0, "A disconnected Bluetooth charge report is not proof of USB power");
    }
    function test_power_agar_usb_match_requires_identity_and_freshness() {
      const keyboard = {icon: "input-keyboard", address: "E6:9D:03:3D:7C:3C", dbusPath: "/agar",
        connected: false, batteryAvailable: false};
      power.bluetoothDevices = [keyboard];
      telemetry.usbDevices = [{vendorId: "9d5b", productId: "2565", serial: "wrong"}];
      verify(!power.keyboardPluggedIn(keyboard));
      telemetry.usbDevices = [{vendorId: "9d5b", productId: "2565", serial: "0D37F50E477AF37B"}];
      verify(power.keyboardPluggedIn(keyboard)); compare(power.keyboardBatteries.length, 1);
      telemetry.systemFresh = false; verify(!power.keyboardPluggedIn(keyboard)); compare(power.keyboardBatteries.length, 0);
    }
    function test_mouse_battery_uses_bluetooth_and_hidpp_charge_state() {
      const mouse = {icon: "input-mouse", address: "MOUSE", dbusPath: "/mouse", deviceName: "MX Anywhere 3S",
        connected: true, batteryAvailable: true, battery: 0.35};
      power.bluetoothDevices = [mouse];
      compare(power.mouseBatteries.length, 1); compare(power.mouseBatteries[0].percent, 35);
      verify(!power.mouseBatteries[0].pluggedIn);
      const report = {type: UPowerDeviceType.Mouse, ready: true, isPresent: true, model: "MX Anywhere 3S",
        nativePath: "hidpp_battery_0", percentage: 0.35, state: UPowerDeviceState.Charging};
      power.powerDevices = [report]; verify(power.mouseBatteries[0].pluggedIn);
      power.bluetoothDevices = [Object.assign({}, mouse, {batteryAvailable: false})];
      compare(power.mouseBatteries[0].percent, 35, "HID++ supplies the level while BlueZ has no report");
      power.bluetoothDevices = [Object.assign({}, mouse, {connected: false})];
      compare(power.mouseBatteries.length, 1, "A charging mouse stays visible");
      power.powerDevices = [Object.assign({}, report, {state: UPowerDeviceState.Discharging})];
      compare(power.mouseBatteries.length, 0, "A stale report cannot keep a disconnected mouse visible");
    }
    function test_mouse_battery_handles_zero_unknown_and_ambiguous_devices() {
      const mouse = {icon: "input-mouse", address: "MOUSE", dbusPath: "/mouse", name: "MX Anywhere 3S",
        connected: true, batteryAvailable: true, battery: 0};
      power.bluetoothDevices = [mouse]; compare(power.mouseBatteries[0].percent, 0);
      for (const value of [null, NaN, undefined, Infinity, -1, 1.01, "0.5"]) {
        power.bluetoothDevices = [Object.assign({}, mouse, {battery: value})];
        compare(power.mouseBatteries.length, 1); compare(power.mouseBatteries[0].percent, null);
      }
      power.bluetoothDevices = [mouse, Object.assign({}, mouse, {address: "OTHER", dbusPath: "/other"})];
      power.powerDevices = [{type: UPowerDeviceType.Mouse, ready: true, isPresent: true, model: mouse.name,
        nativePath: "hidpp_battery_0", state: UPowerDeviceState.Charging}];
      verify(!power.mouseBatteries.some(device => device.pluggedIn));
      power.powerDevices = [{ready: true, isPresent: true, nativePath: "/mouse", state: UPowerDeviceState.Charging}];
      verify(power.mouseBatteries[0].pluggedIn); verify(!power.mouseBatteries[1].pluggedIn);
      compare(power.accessoryBatteries.length, 2);
    }
    function test_mouse_full_charge_requires_an_explicit_hidpp_state_not_100_percent() {
      const mouse = {icon: "input-mouse", address: "MOUSE", deviceName: "MX Anywhere 3S",
        connected: true, batteryAvailable: true, battery: 1};
      const report = {type: UPowerDeviceType.Mouse, ready: true, isPresent: true, model: mouse.deviceName,
        nativePath: "hidpp_battery_0", percentage: 1};
      power.bluetoothDevices = [mouse];
      compare(power.mouseBatteries[0].pluggedIn, null);
      for (const state of [UPowerDeviceState.Charging, UPowerDeviceState.PendingCharge]) {
        power.powerDevices = [Object.assign({}, report, {state: state})];
        compare(power.mouseBatteries[0].percent, 100); verify(power.mouseBatteries[0].pluggedIn);
      }
      power.powerDevices = [Object.assign({}, report, {state: UPowerDeviceState.Discharging})];
      compare(power.mouseBatteries[0].percent, 100); compare(power.mouseBatteries[0].pluggedIn, false);
      power.powerDevices = [Object.assign({}, report, {state: UPowerDeviceState.Unknown})];
      compare(power.mouseBatteries[0].pluggedIn, null);
      power.powerDevices = [Object.assign({}, report, {state: UPowerDeviceState.FullyCharged})];
      compare(power.mouseBatteries[0].pluggedIn, null, "UPower full at 100% is not evidence of external power");
      telemetry.hidppBatteries = [{nativePath: "hidpp_battery_0", status: "Discharging"}];
      compare(power.mouseBatteries[0].pluggedIn, false);
      telemetry.hidppBatteries = [{nativePath: "hidpp_battery_0", status: "Full"}];
      compare(power.mouseBatteries[0].pluggedIn, true, "The kernel's explicit charge-complete status confirms power");
      telemetry.systemFresh = false;
      compare(power.mouseBatteries[0].pluggedIn, null);
      telemetry.systemFresh = true;
      telemetry.hidppBatteries = [{nativePath: "hidpp_battery_1", status: "Full"}];
      compare(power.mouseBatteries[0].pluggedIn, null, "Another device's report must not be used");
      power.bluetoothDevices = [Object.assign({}, mouse, {connected: false})];
      compare(power.mouseBatteries.length, 0);
      telemetry.hidppBatteries = [{nativePath: "hidpp_battery_0", status: "Full"}];
      compare(power.mouseBatteries.length, 1); verify(power.mouseBatteries[0].pluggedIn);
      power.powerDevices = [Object.assign({}, report, {state: UPowerDeviceState.FullyCharged, isPresent: false})];
      compare(power.mouseBatteries.length, 0);
    }
    function test_pixel_buds_battery_tracks_connection_and_missing_reports() {
      const buds = {name: "Ian's Pixel Buds Pro 2", deviceName: "Pixel Buds Pro 2",
        address: "BUDS", dbusPath: "/buds", connected: true, batteryAvailable: true, battery: 0.73};
      const keyboard = {icon: "input-keyboard", address: "KEYBOARD", dbusPath: "/keyboard",
        connected: true, batteryAvailable: true, battery: 0.45};
      power.bluetoothDevices = [keyboard, buds];
      compare(power.keyboardBatteries.length, 1);
      compare(power.earbudBatteries.length, 1); compare(power.accessoryBatteries.length, 2);
      compare(power.earbudBatteries[0].name, buds.name);
      compare(power.earbudBatteries[0].percent, 73); verify(!power.earbudBatteries[0].pluggedIn);
      power.bluetoothDevices = [Object.assign({}, buds, {battery: 0})];
      compare(power.earbudBatteries[0].percent, 0);
      for (const report of [{batteryAvailable: false}, {battery: NaN}, {battery: null}, {battery: -1}, {battery: 1.01}]) {
        power.bluetoothDevices = [Object.assign({}, buds, report)];
        compare(power.earbudBatteries.length, 1); compare(power.earbudBatteries[0].percent, null);
      }
      power.bluetoothDevices = [Object.assign({}, buds, {connected: false})];
      compare(power.earbudBatteries.length, 0); compare(power.accessoryBatteries.length, 0);
      power.bluetoothDevices = [Object.assign({}, buds, {name: "My earbuds"})];
      compare(power.earbudBatteries.length, 1, "The original name survives an alias change");
      power.bluetoothDevices = [Object.assign({}, buds, {name: "Another headset", deviceName: "Other headset"})];
      compare(power.earbudBatteries.length, 0);
    }
    function phoneSample(level, pluggedIn = false, charging = false) {
      const relay = power.phoneRelay;
      relay.accept({event: "connection", connected: true});
      return relay.accept({event: "battery", device: "phone", percent: level, pluggedIn, charging,
        updatedAt: relay.now + 2000, receivedAt: relay.now});
    }
    function test_phone_battery_uses_only_precise_relay_values() {
      power.bluetoothDevices = [{address: "OLD-PHONE", icon: "phone", connected: true, batteryAvailable: true, battery: 0.8}];
      telemetry.usbDevices = [{vendorId: "phone-vendor", serial: "phone-usb"}];
      compare(power.phoneBatteries.length, 0, "Native phone battery and USB cannot create a reading");
      for (const level of [0, 1, 19, 39, 40, 73, 95, 100]) {
        verify(phoneSample(level));
        compare(power.phoneBatteries.length, 1); compare(power.phoneBatteries[0].percent, level);
        compare(power.phoneBatteries[0].lowThreshold, 40);
        compare(power.phoneBatteries[0].name, "Pixel 8 Pro");
      }
      verify(!power.phoneBatteries[0].pluggedIn, "100% does not imply external power");
      telemetry.usbDevices = [];
      verify(phoneSample(95, true, true));
      verify(power.phoneBatteries[0].pluggedIn); verify(power.phoneBatteries[0].charging);
    }
    function test_phone_disconnect_never_falls_back_to_other_providers() {
      power.bluetoothDevices = [{address: "OLD-PHONE", icon: "phone", connected: true, batteryAvailable: true, battery: 0.8}];
      power.powerDevices = [{ready: true, isPresent: true, nativePath: "/phone", state: UPowerDeviceState.Charging}];
      telemetry.usbDevices = [{vendorId: "phone-vendor", serial: "phone-usb"}];
      verify(phoneSample(73, true, true));
      power.phoneRelay.accept({event: "connection", connected: false});
      compare(power.phoneBatteries.length, 0); compare(power.accessoryBatteries.length, 0);
      power.phoneRelay.accept({event: "connection", connected: true});
      compare(power.phoneBatteries.length, 0, "A connection report is not a measurement");
      verify(phoneSample(74, false, false)); compare(power.phoneBatteries[0].percent, 74);
    }
    function test_phone_unknown_and_charge_states_come_from_the_relay() {
      verify(phoneSample(null, null, null));
      compare(power.phoneBatteries.length, 1); compare(power.phoneBatteries[0].percent, null);
      compare(power.phoneBatteries[0].pluggedIn, null); compare(power.phoneBatteries[0].charging, null);
      verify(phoneSample(100, true, false));
      verify(power.phoneBatteries[0].pluggedIn); compare(power.phoneBatteries[0].charging, false);
      power.phoneRelay.invalidate();
      compare(power.phoneBatteries.length, 0);
    }
    function test_phone_stale_or_invalid_reading_is_removed() {
      verify(phoneSample(73, true, true));
      power.phoneRelay.now += power.phoneRelay.staleAfterMs;
      compare(power.phoneBatteries.length, 0);
      verify(phoneSample(74, false, false)); compare(power.phoneBatteries.length, 1);
      verify(!phoneSample(101)); compare(power.phoneBatteries.length, 0);
    }
    function test_pixel_buds_full_battery_is_not_assumed_to_be_charging() {
      power.bluetoothDevices = [{name: "Pixel Buds Pro", address: "BUDS", dbusPath: "/buds",
        connected: true, batteryAvailable: true, battery: 1}];
      compare(power.earbudBatteries[0].percent, 100); verify(!power.earbudBatteries[0].pluggedIn);
      power.powerDevices = [{ready: true, isPresent: true, nativePath: "/buds", state: UPowerDeviceState.Charging}];
      verify(power.earbudBatteries[0].pluggedIn);
      power.powerDevices = [];
      verify(!power.earbudBatteries[0].pluggedIn);
      power.powerDevices = [{ready: true, isPresent: true, nativePath: "/buds", state: UPowerDeviceState.FullyCharged}];
      compare(power.earbudBatteries[0].pluggedIn, null, "Full alone does not confirm the case is powered");
    }
  }
}
