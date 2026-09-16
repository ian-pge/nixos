// Exercise the actual StatusData QML JS functions without starting its services.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const source = readFileSync(new URL("../StatusData.qml", import.meta.url), "utf8");
function method(name) {
  const match = source.match(new RegExp(`^  function ${name}\\([^]*?^  }`, "m"));
  assert.ok(match, `Missing StatusData function ${name}`);
  return match[0];
}
const methods = ["resolveTargetMonitor", "visibleCenterModeWithoutVoice", "visibleCenterMode",
  "monitorForCenterMode", "notificationCoversMonitor", "beginCenterTransition", "finishCenterTransition",
  "showSystemPanel", "hideSystemPanel", "toggleSystemPanel", "showCalendar", "hideCalendar",
  "toggleAudioSelector", "hideAudioSelector", "restorePolkitPreviousOverlay",
  "systemProcessListsWanted", "sendSystemProcessRequest", "syncSystemProcessLists"];
const overlays = { AppLauncher: "appLauncherVisible", ChromeTabs: "chromeTabsVisible",
  MediaOverlay: "mediaOverlayVisible", WifiSelector: "wifiSelectorVisible",
  BluetoothSelector: "bluetoothSelectorVisible", UpdateSelector: "updateSelectorVisible",
  VolumeOverlay: "volumeOverlayVisible", BrightnessOverlay: "brightnessOverlayVisible" };
const state = {
  Hyprland: { focusedMonitor: {name: "DP-2"}, monitors: {values: [{name: "DP-2"}, {name: "eDP-1"}]} },
  systemPanelVisible: false, systemTargetMonitor: "", calendarVisible: false, calendarTargetMonitor: "",
  audioSelectorVisible: false, audioTargetMonitor: "", voiceDictationActive: false,
  voiceDictationTargetMonitor: "DP-2", centerTransitionPending: false, centerTransitionSerial: 0,
  weatherData: { sessionCount: 0, beginCalendarSession() { this.sessionCount++; },
    refreshIfNeeded() {}, closeLocationSearch() {} }, calendarGoToday() {},
  polkitPreviousMode: "", polkitPreviousMonitor: "",
  polkitActive: false, notificationData: {
    visible: false, targetMonitor: "DP-2", closeCount: 0,
    close() { this.visible = false; this.closeCount++; }
  },
  systemData: {topRequestId:7},
  systemStatsProcess: {writes:[],write(line){this.writes.push(line);}},
  gpuProcess: {writes:[],write(line){this.writes.push(line);}},
};
for (const [suffix, property] of Object.entries(overlays)) {
  state[property] = false;
  state[`hide${suffix}`] = () => { state[property] = false; };
}
vm.createContext(state);
vm.runInContext(methods.map(method).join("\n"), state);

state.toggleSystemPanel();
assert.equal(state.systemTargetMonitor, "DP-2");
assert.equal(state.visibleCenterMode(), "system");
assert.equal(state.centerTransitionSerial, 1);
state.toggleSystemPanel("eDP-1");
assert.equal(state.systemTargetMonitor, "eDP-1");
assert.ok(state.systemPanelVisible);
assert.equal(state.centerTransitionSourceMonitor, "DP-2");
assert.equal(state.centerTransitionTargetMonitor, "eDP-1");
state.toggleSystemPanel("eDP-1");
assert.equal(state.visibleCenterMode(), "workspaces");
assert.equal(state.centerTransitionSerial, 3);

state.showCalendar("DP-2");
state.showSystemPanel("eDP-1");
assert.ok(!state.calendarVisible && state.systemPanelVisible);
assert.equal(state.centerTransitionSourceMode, "calendar");
assert.equal(state.centerTransitionTargetMode, "system");
state.showCalendar("DP-2");
assert.ok(state.calendarVisible && !state.systemPanelVisible);
state.notificationData.visible = true;
state.notificationData.targetMonitor = "DP-2";
state.showSystemPanel("DP-2");
assert.ok(state.systemPanelVisible && !state.notificationData.visible,
  "An explicit widget must immediately replace a notification on its monitor");
assert.equal(state.notificationData.closeCount, 1);
state.notificationData.visible = true;
state.toggleSystemPanel("DP-2");
assert.ok(state.systemPanelVisible,
  "A shortcut must reveal an already-open widget hidden by a notification");
assert.equal(state.notificationData.closeCount, 2);
state.showSystemPanel("DP-2");
state.toggleAudioSelector("eDP-1");
assert.ok(state.audioSelectorVisible && !state.systemPanelVisible);
state.showSystemPanel("DP-2");
assert.ok(!state.audioSelectorVisible && state.systemPanelVisible);

state.voiceDictationActive = true;
assert.equal(state.visibleCenterMode(), "dictation");
assert.equal(state.visibleCenterModeWithoutVoice(), "system");
state.voiceDictationActive = false;
assert.equal(state.visibleCenterMode(), "system");
state.hideSystemPanel();
state.polkitPreviousMode = "system";
state.polkitPreviousMonitor = "eDP-1";
state.restorePolkitPreviousOverlay();
assert.ok(state.systemPanelVisible);
assert.equal(state.systemTargetMonitor, "eDP-1");
assert.equal(state.monitorForCenterMode("system"), "eDP-1");

assert.ok(state.systemProcessListsWanted());
state.notificationData.visible = true;
assert.ok(state.systemProcessListsWanted(), "A notification on another monitor must not pause the visible panel");
state.notificationData.targetMonitor = "eDP-1";
assert.ok(!state.systemProcessListsWanted());
state.notificationData.visible = false;
state.voiceDictationActive = true; state.voiceDictationTargetMonitor = "eDP-1";
assert.ok(!state.systemProcessListsWanted());
state.voiceDictationActive = false; state.polkitActive = true;
assert.ok(!state.systemProcessListsWanted());
state.polkitActive = false;
state.syncSystemProcessLists();
assert.deepEqual(state.systemStatsProcess.writes,["7\n"]);
assert.deepEqual(state.gpuProcess.writes,["7\n"]);
state.systemData.topRequestId = 0;
state.syncSystemProcessLists();
assert.equal(state.systemStatsProcess.writes.at(-1),"0\n");
assert.equal(state.gpuProcess.writes.at(-1),"0\n");
state.hideSystemPanel();
assert.ok(!state.systemProcessListsWanted());
assert.equal((source.match(/onStarted: root.sendSystemProcessRequest/g) || []).length,2,
  "Both restarted collectors must receive the current subscription");

for (const name of ["showAppLauncher", "showChromeTabs", "toggleAudioSelector", "showCalendar",
  "showVolumeOverlay", "showBrightnessOverlay", "showWifiSelector", "showBluetoothSelector", "showUpdateSelector"])
  assert.match(method(name), /hideSystemPanel\(\)/, `${name} must close the system panel`);
for (const name of ["toggleAppLauncher", "toggleChromeTabs", "toggleAudioSelector",
  "toggleSystemPanel", "toggleCalendar", "toggleWifiSelector",
  "toggleBluetoothSelector", "toggleUpdateSelector"])
  assert.match(method(name), /!notificationCoversMonitor\(resolvedTarget\)/,
    `${name} must reveal a widget already hidden by a notification`);
assert.match(method("beginCenterTransition"), /notificationData\.close\(\)/,
  "Every explicit center widget must replace a notification on its monitor");
assert.match(method("showMediaOverlay"), /systemPanelVisible/, "Automatic media must not cover the system panel");
assert.match(source, /root\.systemPanelVisible && !Hyprland\.monitors\.values\.some\(monitor => monitor\.name === root\.systemTargetMonitor\)\)\s+root\.hideSystemPanel\(\)/,
  "Removing the target monitor must close the panel");
state.hideSystemPanel();
state.hideCalendar();
const sessionsBefore = state.weatherData.sessionCount;
state.showCalendar("DP-2");
assert.equal(state.weatherData.sessionCount, sessionsBefore + 1);
state.showCalendar("eDP-1");
assert.equal(state.weatherData.sessionCount, sessionsBefore + 1, "Moving an open calendar must preserve the searched city");
state.hideCalendar();
state.showCalendar("eDP-1", false);
assert.equal(state.weatherData.sessionCount, sessionsBefore + 1, "Restoring after polkit must preserve the searched city");
state.hideCalendar();
state.showCalendar("DP-2");
assert.equal(state.weatherData.sessionCount, sessionsBefore + 2, "Reopening must redetect the current location");
console.log("PASS: system panel, overlay restoration and automatic weather location on calendar reopening");
