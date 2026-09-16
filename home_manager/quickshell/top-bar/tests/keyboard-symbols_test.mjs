// Validate the HHKB diagram and real Lafayette latch/Compose behavior.
// Usage: node keyboard-symbols_test.mjs keymap.xkb [python3] [libxkbcommon.so.0]
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

assert(process.argv[2], "provide the Lafayette keymap built by hyprland/lafayette.nix");
const layout = vm.createContext({});
vm.runInContext(readFileSync(new URL("../components/KeyboardLayout.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/, ""), layout);
const levels = JSON.parse(execFileSync(process.argv[3] || "python3", [
  fileURLToPath(new URL("./lafayette-xkb_test.py", import.meta.url)),
  process.argv[4] || "libxkbcommon.so.0"
], { input: readFileSync(process.argv[2]), encoding: "utf8" }));
const keys = layout.rows.flat().filter(key => key.group !== "gap");
assert.equal(keys.length, 60, "HHKB has 60 physical keys");
for (const row of layout.rows) assert.equal(row.reduce((sum, key) => sum + key.units, 0), 15);
let compared = 0;
for (const key of keys.filter(key => key.symbols.length)) {
  const expected = levels[key.label];
  assert(expected, `XKB key missing for ${key.label}`);
  assert.deepEqual(Array.from(key.symbols), expected, `Character levels on ${key.label}`);
  for (let index = 0; index < expected.length; index++) {
    const uppercase = index % 2 === 1 && expected[index] !== expected[index].toLowerCase();
    assert.equal(key.displaySymbols[index], uppercase ? "" : expected[index],
      `Only uppercase letters should be hidden on ${key.label}, level ${index}`);
  }
  compared++;
}
assert.equal(compared, 47, "every character key must be covered");
assert.equal(layout.rows[1].at(-1).label, "Backspace");
assert.equal(layout.rows[3].at(-1).label, "Delete");
assert.equal(layout.rows[4].at(-2).label, "Fn");
assert.equal(layout.rows[4][2].label, "⌘ Cmd");
assert.equal(layout.rows[4][4].label, "AltGr");
assert.equal(keys.find(key => key.label === "'").action, "Cette aide");
assert.equal(keys.find(key => key.label === ";").action, "");
assert.equal(keys.find(key => key.label === "P").action, "Onglets");
console.log(`PASS: all ${compared} Lafayette character keys match XKB; released ★, uppercase, AltGr and double ★ verified`);
