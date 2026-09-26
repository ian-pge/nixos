import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { execFileSync } from "node:child_process";

const context = vm.createContext({});
vm.runInContext(readFileSync(new URL("../features/audio/AudioRoutes.js", import.meta.url), "utf8"), context);
const { updateObjects, unavailableSources } = context;
const objects = {};
const route = (available, devices = [1]) => ({ direction: "Input", devices, available });
const routes = values => ({ id: 48, info: { params: { EnumRoute: values } } });
const source = (id, name, profileDevice) => ({
  id, type: "PipeWire:Interface:Node", info: { props: {
    "media.class": "Audio/Source", "node.name": name,
    "device.id": "48", "card.profile.device": profileDevice
  } }
});
const hidden = () => Object.keys(unavailableSources(objects)).sort();

updateObjects(objects, [source(57, "jack", "1"), source(58, "internal", 2),
  source(59, "usb", 3), { id: 48, type: "PipeWire:Interface:Device", info: {} }]);
assert.deepEqual(hidden(), [], "Missing route information must keep sources visible");
updateObjects(objects, [routes([route("no"), route("unknown", [2])])]);
assert.deepEqual(hidden(), ["jack"], "Hide unplugged jack, keep internal and USB sources");
updateObjects(objects, [{ id: 48, info: { props: { "device.description": "Updated" } } }]);
assert.deepEqual(hidden(), ["jack"], "Unrelated updates must preserve availability");
updateObjects(objects, [routes([route("yes"), route("unknown", [2])])]);
assert.deepEqual(hidden(), [], "Plugging in must reveal the jack");
updateObjects(objects, [routes([route("no"), route("unknown")])]);
assert.deepEqual(hidden(), [], "One potentially usable route must keep a source visible");
updateObjects(objects, [routes([route("no")])]);
assert.deepEqual(hidden(), ["jack"], "Unplugging again must hide the jack");
updateObjects(objects, [{ id: 57, info: null }]);
assert.deepEqual(hidden(), [], "Removed nodes must not retain stale availability");
updateObjects(objects, [source(57, "replacement", 1), { id: 48, info: null }]);
assert.deepEqual(hidden(), [], "Removed devices must not affect reused node IDs");

if (process.argv.includes("--live")) {
  const live = {};
  updateObjects(live, JSON.parse(execFileSync("pw-dump", ["--no-colors"], { encoding: "utf8" })));
  console.log("Currently unavailable sources:", Object.keys(unavailableSources(live)));
}
console.log("Audio route availability checks passed");
