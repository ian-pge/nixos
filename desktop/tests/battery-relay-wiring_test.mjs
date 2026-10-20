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
assert.doesNotMatch(read("../tools/battery-relay/receiver/src/bin/fast-pair-battery.rs"),
  /\.connect\(|\.pair\(|set_powered|set_trusted|remove_device|register_agent/);
console.log("PASS: independent phone/Fitbit and read-only Fast Pair sources, shared across monitors");
