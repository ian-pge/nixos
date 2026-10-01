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
  QtObject { id: telemetry; property bool systemFresh: true; property var usbDevices: [] }
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
      telemetry.systemFresh = true; telemetry.usbDevices = [];
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
      for (const report of [{batteryAvailable: false}, {battery: NaN}, {battery: null}]) {
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
    function test_pixel_buds_full_battery_is_not_assumed_to_be_charging() {
      power.bluetoothDevices = [{name: "Pixel Buds Pro", address: "BUDS", dbusPath: "/buds",
        connected: true, batteryAvailable: true, battery: 1}];
      compare(power.earbudBatteries[0].percent, 100); verify(!power.earbudBatteries[0].pluggedIn);
      power.powerDevices = [{ready: true, isPresent: true, nativePath: "/buds", state: UPowerDeviceState.Charging}];
      verify(power.earbudBatteries[0].pluggedIn);
      power.powerDevices = [];
      verify(!power.earbudBatteries[0].pluggedIn);
    }
  }
}
