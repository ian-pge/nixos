import assert from "node:assert/strict";
import {existsSync, readFileSync} from "node:fs";

const read = file => readFileSync(new URL("../" + file, import.meta.url), "utf8");
const power = read("features/power/PowerController.qml");
assert.equal((read("shell.qml").match(/\bPowerController\s*\{/g) || []).length, 1);
assert.equal((power.match(/\bBatteryRelayData\s*\{/g) || []).length, 1,
  "One phone receiver is shared by all monitors");
assert.match(power, /readonly property var phoneBatteries:\s*relay\.connected/);
assert.match(power, /readonly property var fitbitBatteries:\s*relay\.fitbitAvailable/);
assert.match(read("bar/Bar.qml"), /objectName: index === 0 \? "fitbitBatteryPill"/);
assert.doesNotMatch(power, /phonePluggedIn|device\.icon === "phone"|20% steps/,
  "No native Bluetooth/USB phone source remains, even as a fallback");
assert.doesNotMatch(read("bar/Bar.qml"), /\bBatteryRelayData\s*\{/,
  "A second monitor must not launch a second receiver");
assert.equal((power.match(/\bFastPairBatteryData\s*\{/g) || []).length, 1,
  "One independent Fast Pair reader is shared by all monitors");
assert.doesNotMatch(read("bar/Bar.qml"), /\bFastPairBatteryData\s*\{/);
assert.doesNotMatch(read("features/power/BatteryRelayData.qml"), /earbudsSnapshot|earbudsAvailable/,
  "The phone stream no longer owns earbuds data");
for (const file of ["features/power/EarbudBatteryData.qml", "tests/tst_EarbudBatteryData.qml",
    "../tools/pixel-buds-battery", "../packages/pixel-buds-battery.nix"])
  assert.equal(existsSync(new URL("../" + file, import.meta.url)), false, "Removed source must stay absent: " + file);
for (const file of ["../packages/default.nix", "../packages/quickshell/desktop.nix", "../home_manager/quickshell.nix"])
  assert.doesNotMatch(read(file), /pixelBudsBattery|pixel-buds-battery/, "Removed package must not be installed: " + file);
assert.match(power, /batteryReading\(name, true, values\.case\.percent/);
assert.match(power, /\[values\.case, values\.left, values\.right\]\.some/);
assert.match(power, /earbudBatteries: earbuds\.available\s*\?\s*\[earbudReading\("Pixel Buds", earbuds\.snapshot\)\]\s*:\s*\[\]/);
assert.match(power, /earbudDataConnected: earbuds\.available/);
assert.match(power, /audioConnected: root\.earbudAudioConnected/);
assert.match(read("bar/Bar.qml"), /delegate: EarbudBatteryWidget/);
assert.match(read("bar/EarbudBatteryWidget.qml"), /iconName: "check"/);
assert.match(read("features/audio/AudioController.qml"), /api\.bluez5\.address/);
assert.doesNotMatch(read("../tools/battery-relay/receiver/src/bin/fast-pair-battery.rs"),
  /\.connect\(|\.pair\(|set_powered|set_trusted|remove_device|register_agent/);
assert.doesNotMatch(read("../tools/battery-relay/receiver/src/bin/fast-pair-battery.rs"),
  /discover_devices|set_discovery_filter|StartDiscovery|DiscoveryFilter|resilient_discovery/,
  "Earbud observation must never reopen an active discovery session");
assert.match(read("../tools/battery-relay/receiver/src/observer.rs"), /adapter\.monitor\(\)/);
for (const file of ["../tools/battery-relay/receiver/src/main.rs", "../tools/battery-relay/receiver/src/observer.rs"])
  assert.doesNotMatch(read(file), /discover_devices|set_discovery_filter|\.connect\(|\.disconnect\(|\.pair\(|\.notify\(|register_agent|set_powered|set_trusted|RecoveryLink/,
    "Both battery sources must be passive, without connected transport recovery");
const android = read("../tools/battery-relay/android/app/src/main/java/dev/ian/ble/RelayService.kt");
assert.match(android, /setConnectable\(false\)\.setScannable\(false\)/);
assert.doesNotMatch(android, /BluetoothGatt|SnapshotQueue|HEARTBEAT_MS|cancelConnection|EXTRA_ADDRESS|KEY_ADDRESS/);
assert.doesNotMatch(android, /InstallationCleanup|pc_address/);
assert.doesNotMatch(read("../tools/battery-relay/android/app/src/main/java/dev/ian/ble/MainActivity.kt"), /InstallationCleanup/);
for (const file of [
    "../tools/battery-relay/android/app/src/main/java/dev/ian/ble/InstallationCleanup.kt",
    "../tools/battery-relay/android/app/src/test/java/dev/ian/ble/InstallationCleanupTest.kt"])
  assert.equal(existsSync(new URL("../" + file, import.meta.url)), false, "Completed migration must remain retired: " + file);
assert.doesNotMatch(read("../tools/battery-relay/receiver/Cargo.toml"), /test-util/);
for (const file of ["features/power/BatteryRelayData.qml", "features/power/FastPairBatteryData.qml"]) {
  assert.match(read(file), /configurationError = exitCode === 78/);
  assert.match(read(file), /enabled && configured && !configurationError/);
}
assert.doesNotMatch(read("features/power/BatteryRelayData.qml"), /report\.event === "connection"|report\.event === "battery"/);
assert.equal(existsSync(new URL("../../tools/battery-relay/receiver/src/discovery.rs", import.meta.url)), false,
  "The retired active discovery supervisor must not remain as a fallback");
assert.match(read("../system/bluetooth.nix"), /settings\.General\.Experimental = true/);
assert.match(read("../system/bluetooth.nix"), /disabledPlugins\s*=\s*\[\s*"rap"\s*\]/,
  "The unused experimental ranging profile must not interfere with the unpaired phone relay");
assert.doesNotMatch(read("../system/bluetooth.nix"), /KernelExperimental\s*=\s*true/);
console.log("PASS: independent phone/Fitbit and passive Fast Pair sources, with no active-scan fallback");
