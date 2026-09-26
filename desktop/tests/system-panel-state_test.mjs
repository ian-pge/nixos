// Structural contracts complement the real QML policy tests in tst_ShellCoordinator.
import assert from "node:assert/strict";
import {readFileSync, existsSync, readdirSync} from "node:fs";
const read = file => readFileSync(new URL("../" + file, import.meta.url), "utf8");
const bar = read("bar/Bar.qml"), capsule = read("bar/CentralCapsule.qml");
const shell = read("shell.qml"), host = read("shell/MessengerHost.qml");
assert.ok(!existsSync(new URL("../shell/StatusData.qml", import.meta.url)), "No legacy state façade");
assert.doesNotMatch(shell + bar + capsule, /statusData|StatusData/);
assert.match(bar, /CentralCapsule\s*\{/);
assert.match(bar, /item: messengerSurface\.presented \? messengerSurface\.surfaceItem : null/);
assert.match(bar, /sourceWidth: centerMorph\.width/);
assert.match(bar, /sourceHeight: centerMorph\.height/);
assert.match(capsule, /targetWidth: Math\.min\(preferredWidth, maximumWidth\)/);
assert.match(capsule, /maximumWidth: workspaceSwitcher\.expandedImplicitWidth/);
assert.match(capsule, /y: root\.barTopInset/);
assert.match(capsule, /Math\.max\(root\.messengerHost\.originContentOpacity, overlayReveal\)/);
assert.match(capsule, /drawBackground: !root\.messengerHost\.presented \|\| \(root\.messengerHost\.active && overlayReveal > 0\)/);
assert.match(capsule, /returningFromChat: root\.messengerHost\.presented && !root\.messengerHost\.active/);
assert.match(host, /windowFocused: root\.windowFocused && activeFocus/);
assert.doesNotMatch(host, /NotificationPopup|notificationData/,
  "The chat never owns a notification surface");
assert.doesNotMatch(shell + capsule, /inlineMonitor|inlinePresentation/);
for (const type of ["NetworkController", "BluetoothController", "UpdateController", "PolkitController",
  "BrightnessController", "DictationController", "CalendarController", "SystemController", "MediaController",
  "PowerController", "ShellCoordinator", "BeeperData", "MessengerController"]) {
  assert.equal((shell.match(new RegExp("\\b" + type + "\\s*\\{", "g")) || []).length, 1, type + " must be unique per session");
}
const ipc = read("shell/ShellIntegration.qml");
for (const name of readdirSync(new URL("../features/messenger/", import.meta.url)).filter(name => name.endsWith('.qml')))
  assert.doesNotMatch(read("features/messenger/" + name), /\bborder(?:\.|\s*\{)/, "Borderless messenger: " + name);
for (const name of ["toggleBeeper", "dismissNotification", "toggleDoNotDisturb", "refreshNix",
  "mediaPlayPause", "mediaNext", "mediaPrevious", "volumeUp", "volumeDown", "toggleAudioMute",
  "toggleAudio", "toggleCalendar", "toggleMicrophoneMute", "showVolume", "showBrightness",
  "brightnessUp", "brightnessDown", "toggleWifi", "toggleBluetooth", "toggleUpdates",
  "toggleLauncher", "toggleChromeTabs"])
  assert.ok(ipc.includes("function " + name + "("), "Stable IPC command " + name);
assert.match(ipc, /target: "topbar"/);
console.log("PASS: controller ownership, narrow central capsule, independent messenger and stable IPC contracts");
