import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

function load(file, bindings = {}) {
  const context = vm.createContext(bindings);
  const source = readFileSync(new URL("../features/launchers/" + file, import.meta.url), "utf8")
    .replace(/^\.(?:pragma|import).*$/gm, "");
  vm.runInContext(source, context);
  return context;
}

const search = load("LauncherSearch.js");
const windows = load("LauncherWindows.js", { Search: search });
assert.equal(search.normalizeText("École À côté"), "ecole a cote");
assert.equal(search.fuzzyScore({ normalizedName: "terminal", searchText: "terminal shell" }, "terminal"), 10000);
assert.ok(search.fuzzyScore({ normalizedName: "terminal", searchText: "terminal shell" }, "trm") > 0);
assert.equal(search.fuzzyScore({ normalizedName: "terminal", searchText: "terminal shell" }, "zz"), -1);
assert.deepEqual(Array.from(search.identityAliases("chrome-abcdef-default.desktop")), ["chrome-abcdef-default", "crx_abcdef"]);
assert.deepEqual(Array.from(search.identityAliases("crx_abcdef")), ["crx_abcdef", "chrome-abcdef-default"]);

const entry = { id: "org.example.App.desktop", startupClass: "Example", icon: "example" };
const recent = { activated: false, address: "123", wayland: null, lastIpcObject: { class: "Example", focusHistoryID: 2 } };
const old = { activated: false, address: "456", wayland: null, lastIpcObject: { initialClass: "Example", focusHistoryID: 8 } };
assert.equal(windows.forApp(entry, [old, recent]), recent);
old.activated = true;
assert.equal(windows.forApp(entry, [old, recent]), old);
assert.equal(windows.forApp(entry, [{ wayland: null, lastIpcObject: { class: "Other" } }]), null);

const activeTab = { id: "1", title: "Example documentation", url: "https://example.org/docs", active: true, windowId: 3 };
const hiddenTab = { id: "2", title: "Other page", url: "https://other.org", active: false, windowId: 3 };
const browser = { title: "Example documentation - Google Chrome", wayland: null, lastIpcObject: { class: "google-chrome" } };
const unrelated = { title: "Unrelated - Google Chrome", wayland: null, lastIpcObject: { class: "google-chrome" } };
assert.equal(windows.forTab(hiddenTab, [{ tab: activeTab }], [unrelated, browser]), browser);
assert.equal(windows.forTab(null, [], []), null);

const dispatched = [];
windows.focus(recent, command => dispatched.push(command));
assert.deepEqual(dispatched, ['hl.dsp.focus({ window = "address:0x123" })']);
let activated = false;
windows.focus({ address: "", wayland: { activate() { activated = true; } } }, () => assert.fail("Wayland activation needs no dispatch"));
assert.ok(activated);
windows.focus(null, () => assert.fail("Null windows cannot be focused"));
console.log("PASS: launcher normalization, fuzzy scoring, app aliases, window matching and focus dispatch");
