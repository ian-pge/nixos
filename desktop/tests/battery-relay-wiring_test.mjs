import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

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
console.log("PASS: one Battery Relay provider, no legacy phone source or fallback");
