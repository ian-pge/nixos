import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick

Scope {
  id: root

  property int cpuUsage: 0
  property int memoryUsage: 0
  property int diskUsage: 0
  property int brightness: 0

  property string gpuText: "--"
  property string gpuTooltip: "GPU data unavailable"
  property string weatherText: "--°"
  property string weatherTooltip: "Weather unavailable"
  property string nixIcon: ""
  property string nixTooltip: "Checking for updates…"
  property var nixUpdates: []
  property bool nixChecking: true
  property bool updateSelectorVisible: false
  property bool appLauncherVisible: false
  property string appLauncherTargetMonitor: ""
  property string appLauncherQuery: ""
  property int appLauncherSelectedIndex: 0
  property int appToplevelRevision: 0
  property var appCatalog: []
  property var appLauncherResults: []
  property bool chromeTabsVisible: false
  property string chromeTabsTargetMonitor: ""
  property string chromeTabsQuery: ""
  property int chromeTabsSelectedIndex: 0
  property bool chromeTabsLoading: false
  property string chromeTabsMessage: ""
  property string chromeTabsAction: ""
  property string chromeTabsActionTabId: ""
  readonly property bool chromeTabsActionPending: chromeTabsAction !== ""
  property var chromeTabCatalog: []
  property var chromeTabResults: []
  property bool mediaOverlayVisible: false
  property string mediaTargetMonitor: ""
  property bool mprisInitialized: false
  property string updateTargetMonitor: ""
  property bool volumeOverlayVisible: false
  property string volumeTargetMonitor: ""
  property bool brightnessOverlayVisible: false
  property string brightnessTargetMonitor: ""
  property bool wifiSelectorVisible: false
  property int wifiSelectedIndex: 0
  property string wifiSelectedSsid: ""
  property int wifiSelectionDirection: 1
  property bool wifiLoading: false
  property bool wifiRefreshSilent: false
  property int wifiScanGeneration: 0
  property string wifiMessage: ""
  property string wifiTargetMonitor: ""
  property bool wifiPasswordMode: false
  property string wifiPassword: ""
  property var wifiPendingNetwork: null
  property bool wifiConnectionUsedPassword: false
  property bool bluetoothSelectorVisible: false
  property string bluetoothTargetMonitor: ""
  property int bluetoothTab: 0
  property int bluetoothSelectedIndex: 0
  property int bluetoothSelectionDirection: 1
  property bool bluetoothSelectorLoading: false
  property bool bluetoothSelectorScanning: false
  property bool bluetoothSelectorRefreshSilent: false
  property string bluetoothSelectorMessage: ""
  property string bluetoothAction: ""
  property var bluetoothActionDevice: null
  property bool bluetoothStartedDiscovery: false
  readonly property bool centerOverlayVisible: volumeOverlayVisible
    || brightnessOverlayVisible || mediaOverlayVisible || appLauncherVisible
    || chromeTabsVisible || wifiSelectorVisible || bluetoothSelectorVisible
    || updateSelectorVisible
  property int centerTransitionSerial: 0
  property bool centerTransitionPending: false
  property string centerTransitionSourceMode: "workspaces"
  property string centerTransitionSourceMonitor: ""
  property string centerTransitionTargetMode: "workspaces"
  property string centerTransitionTargetMonitor: ""

  onAppLauncherQueryChanged: refreshAppLauncherResults()
  onChromeTabsQueryChanged: refreshChromeTabResults()
  onCenterOverlayVisibleChanged: setFocusedWindowBorder(centerOverlayVisible)

  Component.onCompleted: {
    rebuildAppCatalog();
    setFocusedWindowBorder(false);
  }

  Component.onDestruction: setFocusedWindowBorder(false)

  readonly property var wifiDevice: Networking.devices.values.find(device =>
    device.type === DeviceType.Wifi) ?? null
  readonly property var wiredDevice: Networking.devices.values.find(device =>
    device.type === DeviceType.Wired && device.connected) ?? null
  readonly property var wifiNetworks: {
    if (wifiDevice === null)
      return [];
    const networks = wifiDevice.networks.values.map(network => ({
      "ssid": network.name,
      "strength": Math.round(network.signalStrength * 100),
      "security": WifiSecurityType.toString(network.security),
      "active": network.connected,
      "known": network.known,
      "nativeNetwork": network
    }));
    networks.sort((left, right) => {
      if (left.active !== right.active)
        return left.active ? -1 : 1;
      if (left.strength !== right.strength)
        return right.strength - left.strength;
      return left.ssid.localeCompare(right.ssid);
    });
    return networks;
  }
  readonly property var activeWifiNetwork: wifiNetworks.find(network =>
    network.active) ?? null
  readonly property string networkType: activeWifiNetwork !== null
    ? "wifi" : wiredDevice !== null ? "ethernet"
      : !Networking.wifiEnabled ? "disabled" : "disconnected"
  readonly property string networkName: activeWifiNetwork !== null
    ? activeWifiNetwork.ssid : wiredDevice !== null ? wiredDevice.name
      : !Networking.wifiEnabled ? "Wi-Fi Off" : "Disconnected"
  readonly property int networkStrength: activeWifiNetwork !== null
    ? activeWifiNetwork.strength : wiredDevice !== null ? 100 : 0

  onWifiNetworksChanged: {
    if (wifiNetworks.length === 0) {
      wifiSelectedIndex = 0;
      wifiSelectedSsid = "";
      return;
    }
    const preservedIndex = wifiNetworks.findIndex(network =>
      network.ssid === wifiSelectedSsid);
    wifiSelectedIndex = preservedIndex >= 0 ? preservedIndex
      : Math.min(wifiSelectedIndex, wifiNetworks.length - 1);
    wifiSelectedSsid = wifiNetworks[wifiSelectedIndex].ssid;
  }

  readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
  readonly property var bluetoothSelectorDevices: Bluetooth.devices.values.map(device => ({
    "address": device.address,
    "name": device.name || device.deviceName || device.address,
    "paired": device.paired,
    "connected": device.connected,
    "nativeDevice": device
  })).sort((left, right) => {
    if (left.connected !== right.connected)
      return left.connected ? -1 : 1;
    if (left.paired !== right.paired)
      return left.paired ? -1 : 1;
    return left.name.localeCompare(right.name);
  })
  onBluetoothSelectorDevicesChanged: {
    const devices = currentBluetoothDevices();
    bluetoothSelectedIndex = Math.min(bluetoothSelectedIndex,
      Math.max(0, devices.length - 1));
  }
  readonly property bool bluetoothEnabled: bluetoothAdapter !== null
    && bluetoothAdapter.enabled
  readonly property var connectedBluetoothDevices: Bluetooth.devices.values
    .filter(device => device.connected)
  readonly property bool bluetoothConnected: connectedBluetoothDevices.length > 0
  readonly property string bluetoothTooltip: {
    if (!bluetoothEnabled)
      return "Bluetooth disabled";
    if (!bluetoothConnected)
      return bluetoothAdapter !== null ? bluetoothAdapter.name : "Bluetooth";
    return connectedBluetoothDevices.map(device => {
      const battery = device.batteryAvailable
        ? " (" + Math.round(device.battery * 100) + "%)"
        : "";
      return device.name + battery;
    }).join("\n");
  }

  readonly property var battery: UPower.displayDevice
  readonly property bool batteryAvailable: battery.ready && battery.isPresent
  readonly property int batteryPercent: batteryAvailable
    ? Math.round(battery.percentage * 100)
    : 0
  readonly property var mprisPlayer: {
    const players = Mpris.players.values.filter(player => player.canControl);
    return players.find(player => player.dbusName.includes("playerctld"))
      ?? players.find(player => player.isPlaying)
      ?? players.find(player => player.playbackState === MprisPlaybackState.Paused)
      ?? players[0] ?? null;
  }

  onMprisPlayerChanged: {
    if (mprisPlayer === null)
      hideMediaOverlay();
  }

  readonly property var audioSink: Pipewire.defaultAudioSink
  readonly property var audio: audioSink !== null ? audioSink.audio : null
  readonly property bool audioMuted: audio !== null && audio.muted
  readonly property int audioVolume: audio !== null
    ? Math.round(audio.volume * 100)
    : 0

  readonly property string timeText: Qt.formatDateTime(clock.date, "HH:mm")
  readonly property string dateText: Qt.formatDateTime(clock.date, "MMM dd yyyy")

  function batteryIcon() {
    const percentage = batteryPercent;
    const charging = battery.state === UPowerDeviceState.Charging
      || battery.state === UPowerDeviceState.PendingCharge;

    if (battery.state === UPowerDeviceState.FullyCharged)
      return "󰁹";

    if (charging) {
      if (percentage <= 10)
        return "󰂄";
      if (percentage <= 25)
        return "󰂆";
      if (percentage <= 35)
        return "󰂇";
      if (percentage <= 45)
        return "󰂈";
      if (percentage <= 65)
        return "󰂉";
      if (percentage <= 85)
        return "󰂊";
      if (percentage <= 95)
        return "󰂋";
      return "󰂅";
    }

    if (battery.state === UPowerDeviceState.Empty || percentage <= 5)
      return "󰂃";
    if (percentage <= 15)
      return "󰁺";
    if (percentage <= 25)
      return "󰁻";
    if (percentage <= 35)
      return "󰁼";
    if (percentage <= 45)
      return "󰁽";
    if (percentage <= 55)
      return "󰁾";
    if (percentage <= 65)
      return "󰁿";
    if (percentage <= 75)
      return "󰂀";
    if (percentage <= 85)
      return "󰂁";
    if (percentage <= 95)
      return "󰂂";
    return "󰁹";
  }

  function audioIcon() {
    if (audioMuted)
      return "󰖁";
    if (audioVolume < 34)
      return "󰕿";
    if (audioVolume < 67)
      return "󰖀";
    return "󰕾";
  }

  function brightnessIcon() {
    if (brightness < 34)
      return "󰃞";
    if (brightness < 67)
      return "󰃟";
    return "󰃠";
  }

  function networkIcon() {
    if (networkType === "ethernet")
      return "󰈀";
    if (networkType !== "wifi")
      return "󰤭";
    if (networkStrength < 26)
      return "󰤟";
    if (networkStrength < 51)
      return "󰤢";
    if (networkStrength < 76)
      return "󰤥";
    return "󰤨";
  }

  function normalizeAppText(value) {
    const lowered = (value ?? "").toString().toLowerCase();
    try {
      return lowered.normalize("NFKD").replace(/[\u0300-\u036f]/g, "");
    } catch (error) {
      return lowered;
    }
  }

  function rebuildAppCatalog() {
    const catalog = [];
    const applications = DesktopEntries.applications.values;
    for (let index = 0; index < applications.length; ++index) {
      const entry = applications[index];
      if (entry.noDisplay || entry.name === "")
        continue;
      const keywords = entry.keywords !== undefined
        ? entry.keywords.join(" ") : "";
      const normalizedName = normalizeAppText(entry.name);
      catalog.push({
        "entry": entry,
        "normalizedName": normalizedName,
        "searchText": normalizeAppText(entry.name + " " + entry.genericName
          + " " + keywords + " " + entry.comment)
      });
    }
    catalog.sort((left, right) => left.entry.name.localeCompare(right.entry.name));
    appCatalog = catalog;
    refreshAppLauncherResults();
  }

  function appFuzzyScore(candidate, query) {
    const name = candidate.normalizedName;
    const text = candidate.searchText;
    if (name === query)
      return 10000;

    let score = name.startsWith(query) ? 1200
      : name.includes(query) ? 700 : 0;
    let previous = -1;
    let streak = 0;
    let gaps = 0;

    for (let index = 0; index < query.length; ++index) {
      const position = text.indexOf(query[index], previous + 1);
      if (position < 0)
        return -1;
      const gap = previous < 0 ? position : position - previous - 1;
      gaps += gap;
      streak = gap === 0 ? streak + 1 : 0;
      score += 20 + streak * 14;
      if (position === 0 || " -_./".includes(text[position - 1]))
        score += 45;
      previous = position;
    }

    score -= gaps * 3;
    score -= Math.max(0, name.length - query.length) * 0.2;
    return score;
  }

  function refreshAppLauncherResults() {
    const query = normalizeAppText(appLauncherQuery.trim());
    if (query === "") {
      appLauncherResults = appCatalog.slice();
    } else {
      const ranked = [];
      for (let index = 0; index < appCatalog.length; ++index) {
        const candidate = appCatalog[index];
        const score = appFuzzyScore(candidate, query);
        if (score >= 0)
          ranked.push({ "candidate": candidate, "score": score });
      }
      ranked.sort((left, right) => right.score - left.score
        || left.candidate.entry.name.localeCompare(right.candidate.entry.name));
      appLauncherResults = ranked.map(result => result.candidate);
    }
    appLauncherSelectedIndex = 0;
  }

  function setAppLauncherQuery(query) {
    appLauncherQuery = query;
  }

  function moveAppLauncherSelection(delta) {
    if (appLauncherResults.length === 0)
      return;
    appLauncherSelectedIndex = (appLauncherSelectedIndex + delta
      + appLauncherResults.length) % appLauncherResults.length;
  }

  function normalizeAppIdentity(value) {
    return normalizeAppText(value).trim().replace(/\.desktop$/, "");
  }

  function appIdentityAliases(value) {
    const identity = normalizeAppIdentity(value);
    if (identity === "")
      return [];
    const aliases = [identity];
    let match = identity.match(/^chrome-([a-z]+)-default$/);
    if (match !== null)
      aliases.push("crx_" + match[1]);
    match = identity.match(/^crx_([a-z]+)$/);
    if (match !== null)
      aliases.push("chrome-" + match[1] + "-default");
    return aliases;
  }

  function appToplevelFor(entry) {
    const appIdentities = [];
    [entry.id, entry.startupClass, entry.icon].forEach(value => {
      appIdentityAliases(value).forEach(identity => {
        if (!appIdentities.includes(identity))
          appIdentities.push(identity);
      });
    });
    if (appIdentities.length === 0)
      return null;

    let best = null;
    let bestHistory = Number.MAX_SAFE_INTEGER;
    const toplevels = Hyprland.toplevels.values;
    for (let index = 0; index < toplevels.length; ++index) {
      const toplevel = toplevels[index];
      const ipc = toplevel.lastIpcObject ?? {};
      const windowIdentities = [];
      [ipc["class"], ipc.initialClass,
        toplevel.wayland !== null ? toplevel.wayland.appId : ""].forEach(value => {
        appIdentityAliases(value).forEach(identity => {
          if (!windowIdentities.includes(identity))
            windowIdentities.push(identity);
        });
      });
      if (!windowIdentities.some(identity => appIdentities.includes(identity)))
        continue;
      if (toplevel.activated)
        return toplevel;
      const focusHistory = ipc.focusHistoryID !== undefined
        ? Number(ipc.focusHistoryID) : Number.MAX_SAFE_INTEGER;
      if (best === null || focusHistory < bestHistory) {
        best = toplevel;
        bestHistory = focusHistory;
      }
    }
    return best;
  }

  function launchNewAppInstance(entry) {
    const newWindowAction = entry.actions.find(action => {
      const id = normalizeAppIdentity(action.id);
      const name = normalizeAppText(action.name).trim();
      return id === "new-window" || id === "newwindow"
        || name === "new window" || name === "nouvelle fenetre";
    });
    if (newWindowAction !== undefined)
      newWindowAction.execute();
    else
      entry.execute();
  }

  function launchSelectedApp(index = appLauncherSelectedIndex, forceNew = false) {
    if (appLauncherResults.length === 0)
      return;
    const boundedIndex = Math.max(0, Math.min(index,
      appLauncherResults.length - 1));
    const entry = appLauncherResults[boundedIndex].entry;
    const runningToplevel = forceNew ? null : appToplevelFor(entry);
    hideAppLauncher();
    if (runningToplevel !== null) {
      if (runningToplevel.address !== "") {
        const address = runningToplevel.address.startsWith("0x")
          ? runningToplevel.address : "0x" + runningToplevel.address;
        Hyprland.dispatch("focuswindow address:" + address);
      } else if (runningToplevel.wayland !== null)
        runningToplevel.wayland.activate();
    } else if (forceNew) {
      launchNewAppInstance(entry);
    } else {
      entry.execute();
    }
  }

  function refreshChromeTabResults() {
    const query = normalizeAppText(chromeTabsQuery.trim());
    if (query === "") {
      chromeTabResults = chromeTabCatalog.slice();
    } else {
      const ranked = [];
      for (let index = 0; index < chromeTabCatalog.length; ++index) {
        const candidate = chromeTabCatalog[index];
        const score = appFuzzyScore(candidate, query);
        if (score >= 0)
          ranked.push({ "candidate": candidate, "score": score });
      }
      ranked.sort((left, right) => right.score - left.score
        || left.candidate.tab.title.localeCompare(right.candidate.tab.title));
      chromeTabResults = ranked.map(result => result.candidate);
    }
    chromeTabsSelectedIndex = 0;
  }

  function parseChromeTabsResponse(text) {
    chromeTabsLoading = false;
    try {
      const response = JSON.parse(text.trim());
      if (!response.ok) {
        chromeTabCatalog = [];
        chromeTabsMessage = response.error || "Unable to contact Chrome";
        refreshChromeTabResults();
        return;
      }

      const tabs = Array.isArray(response.tabs) ? response.tabs : [];
      chromeTabCatalog = tabs.filter(tab => tab.id !== undefined)
        .map(tab => {
          const title = (tab.title || tab.url || "Untitled tab").toString();
          const url = (tab.url || "").toString();
          return {
            "tab": tab,
            "normalizedName": normalizeAppText(title),
            "searchText": normalizeAppText(title + " " + url)
          };
        });
      chromeTabsMessage = "";
      refreshChromeTabResults();
    } catch (error) {
      chromeTabCatalog = [];
      chromeTabsMessage = "Unable to read Chrome tabs";
      refreshChromeTabResults();
    }
  }

  function requestChromeTabs() {
    if (chromeTabsProcess.running)
      return;
    chromeTabsLoading = true;
    chromeTabsMessage = "";
    chromeTabCatalog = [];
    refreshChromeTabResults();
    chromeTabsProcess.running = true;
  }

  function setChromeTabsQuery(query) {
    chromeTabsQuery = query;
  }

  function moveChromeTabsSelection(delta) {
    if (chromeTabResults.length === 0)
      return;
    chromeTabsSelectedIndex = (chromeTabsSelectedIndex + delta
      + chromeTabResults.length) % chromeTabResults.length;
  }

  function runChromeTabAction(action, tabId) {
    if (chromeTabsActionPending)
      return;
    chromeTabsAction = action;
    chromeTabsActionTabId = tabId;
    chromeTabsMessage = "";
    if (action === "activate")
      chromeTabsActivationDelay.restart();
    else
      chromeTabsActionProcess.exec(["quickshell-chrome-tabs", action, tabId]);
  }

  function activateSelectedChromeTab(index = chromeTabsSelectedIndex) {
    if (chromeTabsLoading || chromeTabResults.length === 0)
      return;
    const boundedIndex = Math.max(0, Math.min(index,
      chromeTabResults.length - 1));
    runChromeTabAction("activate", chromeTabResults[boundedIndex].tab.id);
  }

  function closeSelectedChromeTab(index = chromeTabsSelectedIndex) {
    if (chromeTabsLoading || chromeTabResults.length === 0)
      return;
    const boundedIndex = Math.max(0, Math.min(index,
      chromeTabResults.length - 1));
    runChromeTabAction("close", chromeTabResults[boundedIndex].tab.id);
  }

  function parseChromeTabActionResponse(text) {
    const action = chromeTabsAction;
    const tabId = chromeTabsActionTabId;
    chromeTabsAction = "";
    chromeTabsActionTabId = "";
    try {
      const response = JSON.parse(text.trim());
      if (!response.ok) {
        chromeTabCatalog = [];
        chromeTabsMessage = response.error || "Chrome tab action failed";
        refreshChromeTabResults();
        return;
      }
      if (action === "activate") {
        hideChromeTabs();
      } else if (action === "close") {
        const previousIndex = chromeTabsSelectedIndex;
        chromeTabCatalog = chromeTabCatalog.filter(candidate =>
          candidate.tab.id !== tabId);
        refreshChromeTabResults();
        if (chromeTabResults.length > 0)
          chromeTabsSelectedIndex = Math.min(previousIndex,
            chromeTabResults.length - 1);
      }
    } catch (error) {
      chromeTabCatalog = [];
      chromeTabsMessage = "Unable to complete Chrome tab action";
      refreshChromeTabResults();
    }
  }

  function resolveTargetMonitor(targetMonitor = "") {
    if (targetMonitor !== "")
      return targetMonitor;
    if (Hyprland.focusedMonitor !== null)
      return Hyprland.focusedMonitor.name;
    return Hyprland.monitors.values.length > 0
      ? Hyprland.monitors.values[0].name : "";
  }

  function visibleCenterMode() {
    if (appLauncherVisible) return "launcher";
    if (chromeTabsVisible) return "tabs";
    if (updateSelectorVisible) return "updates";
    if (wifiSelectorVisible) return "wifi";
    if (bluetoothSelectorVisible) return "bluetooth";
    if (mediaOverlayVisible) return "media";
    if (volumeOverlayVisible) return "volume";
    if (brightnessOverlayVisible) return "brightness";
    return "workspaces";
  }

  function monitorForCenterMode(mode) {
    if (mode === "launcher") return appLauncherTargetMonitor;
    if (mode === "tabs") return chromeTabsTargetMonitor;
    if (mode === "updates") return updateTargetMonitor;
    if (mode === "wifi") return wifiTargetMonitor;
    if (mode === "bluetooth") return bluetoothTargetMonitor;
    if (mode === "media") return mediaTargetMonitor;
    if (mode === "volume") return volumeTargetMonitor;
    if (mode === "brightness") return brightnessTargetMonitor;
    return "";
  }

  function beginCenterTransition(targetMode, targetMonitor = "") {
    if (centerTransitionPending)
      return false;
    const sourceMode = visibleCenterMode();
    const sourceMonitor = monitorForCenterMode(sourceMode);
    const resolvedTargetMonitor = targetMode === "workspaces"
      ? "" : resolveTargetMonitor(targetMonitor);
    if (sourceMode === targetMode && sourceMonitor === resolvedTargetMonitor)
      return false;
    centerTransitionSourceMode = sourceMode;
    centerTransitionSourceMonitor = sourceMonitor;
    centerTransitionTargetMode = targetMode;
    centerTransitionTargetMonitor = resolvedTargetMonitor;
    centerTransitionPending = true;
    return true;
  }

  function finishCenterTransition(ownedTransition) {
    if (!ownedTransition)
      return;
    centerTransitionPending = false;
    centerTransitionSerial++;
  }

  function toggleAppLauncher(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    if (appLauncherVisible && appLauncherTargetMonitor === resolvedTarget)
      hideAppLauncher();
    else
      showAppLauncher(resolvedTarget);
  }

  function showAppLauncher(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    const preserveQuery = appLauncherVisible;
    const ownsTransition = beginCenterTransition("launcher", resolvedTarget);
    hideMediaOverlay();
    hideWifiSelector();
    hideBluetoothSelector();
    hideUpdateSelector();
    hideVolumeOverlay();
    hideBrightnessOverlay();
    hideChromeTabs();
    appLauncherTargetMonitor = resolvedTarget;
    if (!preserveQuery)
      appLauncherQuery = "";
    refreshAppLauncherResults();
    appLauncherVisible = true;
    finishCenterTransition(ownsTransition);
  }

  function hideAppLauncher() {
    if (!appLauncherVisible)
      return;
    const ownsTransition = beginCenterTransition("workspaces");
    appLauncherVisible = false;
    finishCenterTransition(ownsTransition);
  }

  function toggleChromeTabs(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    if (chromeTabsVisible && chromeTabsTargetMonitor === resolvedTarget)
      hideChromeTabs();
    else
      showChromeTabs(resolvedTarget);
  }

  function showChromeTabs(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    const ownsTransition = beginCenterTransition("tabs", resolvedTarget);
    hideAppLauncher();
    hideMediaOverlay();
    hideWifiSelector();
    hideBluetoothSelector();
    hideUpdateSelector();
    hideVolumeOverlay();
    hideBrightnessOverlay();
    chromeTabsTargetMonitor = resolvedTarget;
    chromeTabsQuery = "";
    chromeTabsSelectedIndex = 0;
    chromeTabsVisible = true;
    requestChromeTabs();
    finishCenterTransition(ownsTransition);
  }

  function hideChromeTabs() {
    if (!chromeTabsVisible)
      return;
    const ownsTransition = beginCenterTransition("workspaces");
    chromeTabsVisible = false;
    finishCenterTransition(ownsTransition);
  }

  function showMediaOverlay(targetMonitor = "") {
    if (mprisPlayer === null || appLauncherVisible || chromeTabsVisible
        || wifiSelectorVisible || bluetoothSelectorVisible
        || updateSelectorVisible)
      return;
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    const ownsTransition = beginCenterTransition("media", resolvedTarget);
    hideVolumeOverlay();
    hideBrightnessOverlay();
    mediaTargetMonitor = resolvedTarget;
    mediaOverlayVisible = true;
    mediaOverlayTimer.restart();
    finishCenterTransition(ownsTransition);
  }

  function hideMediaOverlay() {
    if (!mediaOverlayVisible) {
      mediaOverlayTimer.stop();
      return;
    }
    const ownsTransition = beginCenterTransition("workspaces");
    mediaOverlayVisible = false;
    mediaOverlayTimer.stop();
    finishCenterTransition(ownsTransition);
  }

  function mediaPlayPause() {
    if (mprisPlayer === null)
      return;
    if (mprisPlayer.canTogglePlaying)
      mprisPlayer.togglePlaying();
    else if (mprisPlayer.isPlaying && mprisPlayer.canPause)
      mprisPlayer.pause();
    else if (!mprisPlayer.isPlaying && mprisPlayer.canPlay)
      mprisPlayer.play();
    showMediaOverlay();
  }

  function mediaNext() {
    if (mprisPlayer !== null && mprisPlayer.canGoNext) {
      mprisPlayer.next();
      showMediaOverlay();
    }
  }

  function mediaPrevious() {
    if (mprisPlayer !== null && mprisPlayer.canGoPrevious) {
      mprisPlayer.previous();
      showMediaOverlay();
    }
  }

  function setVolume(delta) {
    if (audio === null)
      return;
    audio.volume = Math.max(0, Math.min(1, audio.volume + delta));
  }

  function volumeUp() {
    setVolume(0.02);
    showVolumeOverlay();
  }

  function volumeDown() {
    setVolume(-0.02);
    showVolumeOverlay();
  }

  function toggleAudioMute() {
    if (audio === null)
      return;
    audio.muted = !audio.muted;
    showVolumeOverlay();
  }

  function setFocusedWindowBorder(overlayActive) {
    Quickshell.execDetached(["hyprctl", "keyword", "general:col.active_border",
      overlayActive ? "rgba(888888aa)" : "rgba(33ff33ff)"]);
  }

  function showVolumeOverlay(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    const ownsTransition = beginCenterTransition("volume", resolvedTarget);
    hideAppLauncher();
    hideMediaOverlay();
    hideWifiSelector();
    hideBluetoothSelector();
    hideUpdateSelector();
    hideBrightnessOverlay();
    hideChromeTabs();
    volumeTargetMonitor = resolvedTarget;
    volumeOverlayVisible = true;
    volumeOverlayTimer.restart();
    finishCenterTransition(ownsTransition);
  }

  function hideVolumeOverlay() {
    if (!volumeOverlayVisible) {
      volumeOverlayTimer.stop();
      return;
    }
    const ownsTransition = beginCenterTransition("workspaces");
    volumeOverlayVisible = false;
    volumeOverlayTimer.stop();
    finishCenterTransition(ownsTransition);
  }

  function showBrightnessOverlay(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    const ownsTransition = beginCenterTransition("brightness", resolvedTarget);
    hideAppLauncher();
    hideMediaOverlay();
    hideWifiSelector();
    hideBluetoothSelector();
    hideUpdateSelector();
    hideVolumeOverlay();
    hideChromeTabs();
    brightnessTargetMonitor = resolvedTarget;
    brightnessOverlayVisible = true;
    brightnessOverlayTimer.restart();
    brightnessRefreshProcess.exec(["brightnessctl", "-m"]);
    finishCenterTransition(ownsTransition);
  }

  function hideBrightnessOverlay() {
    if (!brightnessOverlayVisible) {
      brightnessOverlayTimer.stop();
      return;
    }
    const ownsTransition = beginCenterTransition("workspaces");
    brightnessOverlayVisible = false;
    brightnessOverlayTimer.stop();
    finishCenterTransition(ownsTransition);
  }

  function toggleWifiSelector(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    if (wifiSelectorVisible && wifiTargetMonitor === resolvedTarget)
      hideWifiSelector();
    else
      showWifiSelector(resolvedTarget);
  }

  function showWifiSelector(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    if (wifiSelectorVisible && wifiTargetMonitor === resolvedTarget)
      return;
    const ownsTransition = beginCenterTransition("wifi", resolvedTarget);
    if (wifiSelectorVisible)
      hideWifiSelector();
    hideAppLauncher();
    hideMediaOverlay();
    hideBluetoothSelector();
    hideUpdateSelector();
    hideVolumeOverlay();
    hideBrightnessOverlay();
    hideChromeTabs();
    wifiTargetMonitor = resolvedTarget;
    wifiSelectorVisible = true;
    wifiSelectedIndex = 0;
    wifiSelectedSsid = wifiNetworks.length > 0 ? wifiNetworks[0].ssid : "";
    wifiMessage = "";
    refreshWifiNetworks(false, true);
    finishCenterTransition(ownsTransition);
  }

  function hideWifiSelector() {
    const wasVisible = wifiSelectorVisible;
    const ownsTransition = wasVisible
      ? beginCenterTransition("workspaces") : false;
    wifiSelectorVisible = false;
    wifiPasswordMode = false;
    wifiPassword = "";
    wifiConnectionTimer.stop();
    wifiPendingNetwork = null;
    wifiConnectionUsedPassword = false;
    wifiMessage = "";
    stopWifiScan();
    finishCenterTransition(ownsTransition);
  }

  function cancelWifiPassword() {
    wifiPasswordMode = false;
    wifiPassword = "";
    wifiMessage = "";
  }

  function appendWifiPassword(text) {
    wifiPassword += text;
    wifiMessage = "";
  }

  function eraseWifiPassword() {
    wifiPassword = wifiPassword.slice(0, -1);
    wifiMessage = "";
  }

  function setWifiSelection(index, direction) {
    if (wifiNetworks.length === 0)
      return;
    wifiSelectionDirection = direction;
    wifiSelectedIndex = Math.max(0, Math.min(index, wifiNetworks.length - 1));
    wifiSelectedSsid = wifiNetworks[wifiSelectedIndex].ssid;
    wifiPasswordMode = false;
    wifiPassword = "";
    wifiMessage = "";
  }

  function moveWifiSelection(delta) {
    if (wifiNetworks.length === 0)
      return;
    setWifiSelection((wifiSelectedIndex + delta + wifiNetworks.length)
      % wifiNetworks.length, delta >= 0 ? 1 : -1);
  }

  function stopWifiScan() {
    wifiScanGeneration++;
    wifiScanTimer.stop();
    if (wifiDevice !== null && wifiDevice.scannerEnabled)
      wifiDevice.scannerEnabled = false;
    wifiLoading = false;
    wifiRefreshSilent = false;
  }

  function refreshWifiNetworks(forceRescan = false, silent = false) {
    const scanGeneration = ++wifiScanGeneration;
    if (wifiDevice === null) {
      if (!silent)
        wifiMessage = "Wi-Fi device unavailable";
      return;
    }

    wifiRefreshSilent = silent;
    if (!silent) {
      wifiLoading = true;
      wifiMessage = "";
    }

    if (wifiDevice.scannerEnabled)
      wifiDevice.scannerEnabled = false;
    Qt.callLater(() => {
      if (!root.wifiSelectorVisible || root.wifiDevice === null
          || scanGeneration !== root.wifiScanGeneration)
        return;
      root.wifiDevice.scannerEnabled = true;
      wifiScanTimer.restart();
    });
  }

  function toggleBluetoothSelector(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    if (bluetoothSelectorVisible && bluetoothTargetMonitor === resolvedTarget)
      hideBluetoothSelector();
    else
      showBluetoothSelector(resolvedTarget);
  }

  function showBluetoothSelector(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    if (bluetoothSelectorVisible && bluetoothTargetMonitor === resolvedTarget)
      return;
    const ownsTransition = beginCenterTransition("bluetooth", resolvedTarget);
    if (bluetoothSelectorVisible)
      hideBluetoothSelector();
    hideAppLauncher();
    hideMediaOverlay();
    hideWifiSelector();
    hideUpdateSelector();
    hideVolumeOverlay();
    hideBrightnessOverlay();
    hideChromeTabs();
    bluetoothTargetMonitor = resolvedTarget;
    bluetoothSelectorVisible = true;
    bluetoothTab = 0;
    bluetoothSelectedIndex = 0;
    refreshBluetoothSelectorDevices(false, true);
    finishCenterTransition(ownsTransition);
  }

  function hideBluetoothSelector() {
    const wasVisible = bluetoothSelectorVisible;
    const ownsTransition = wasVisible
      ? beginCenterTransition("workspaces") : false;
    bluetoothSelectorVisible = false;
    if (bluetoothActionDevice === null)
      bluetoothSelectorMessage = "";
    stopBluetoothDiscovery();
    finishCenterTransition(ownsTransition);
  }

  function currentBluetoothDevices() {
    return bluetoothSelectorDevices.filter(device => bluetoothTab === 0
      ? device.paired : !device.paired);
  }

  function moveBluetoothSelection(delta) {
    const devices = currentBluetoothDevices();
    if (devices.length === 0)
      return;
    bluetoothSelectionDirection = delta >= 0 ? 1 : -1;
    bluetoothSelectedIndex = (bluetoothSelectedIndex + delta + devices.length)
      % devices.length;
    bluetoothSelectorMessage = "";
  }

  function stopBluetoothDiscovery() {
    bluetoothScanTimer.stop();
    if (bluetoothStartedDiscovery && bluetoothAdapter !== null)
      bluetoothAdapter.discovering = false;
    bluetoothStartedDiscovery = false;
    bluetoothSelectorLoading = false;
    bluetoothSelectorScanning = false;
    bluetoothSelectorRefreshSilent = false;
  }

  function switchBluetoothTab() {
    bluetoothTab = bluetoothTab === 0 ? 1 : 0;
    bluetoothSelectedIndex = 0;
    bluetoothSelectorMessage = "";
    if (bluetoothTab === 1)
      refreshBluetoothSelectorDevices(true, false);
    else
      stopBluetoothDiscovery();
  }

  function refreshBluetoothSelectorDevices(scan, silent = false) {
    if (!scan)
      return;
    if (bluetoothAdapter === null) {
      if (!silent)
        bluetoothSelectorMessage = "Bluetooth adapter unavailable";
      return;
    }

    bluetoothSelectorRefreshSilent = silent;
    if (!silent) {
      bluetoothSelectorLoading = true;
      bluetoothSelectorScanning = true;
      bluetoothSelectorMessage = "";
    }
    if (!bluetoothAdapter.discovering) {
      bluetoothStartedDiscovery = true;
      bluetoothAdapter.discovering = true;
    }
    bluetoothScanTimer.restart();
  }

  function activateSelectedBluetoothDevice() {
    if (bluetoothActionDevice !== null)
      return;
    const devices = currentBluetoothDevices();
    if (devices.length === 0)
      return;
    const device = devices[Math.min(bluetoothSelectedIndex, devices.length - 1)];
    const nativeDevice = device.nativeDevice;
    bluetoothAction = bluetoothTab === 1
      ? "pair" : nativeDevice.connected ? "disconnect" : "connect";
    bluetoothActionDevice = nativeDevice;
    bluetoothSelectorMessage = bluetoothAction === "pair"
      ? "Pairing with " + device.name + "…"
      : bluetoothAction === "connect"
        ? "Connecting to " + device.name + "…"
        : "Disconnecting " + device.name + "…";
    bluetoothActionTimer.restart();

    if (bluetoothAction === "pair")
      nativeDevice.pair();
    else if (bluetoothAction === "connect")
      nativeDevice.connect();
    else
      nativeDevice.disconnect();
  }

  function finishBluetoothAction(succeeded) {
    bluetoothActionTimer.stop();
    if (succeeded) {
      if (bluetoothAction === "pair") {
        if (bluetoothActionDevice !== null)
          bluetoothActionDevice.trusted = true;
        bluetoothTab = 0;
        bluetoothSelectedIndex = 0;
        stopBluetoothDiscovery();
      }
      bluetoothSelectorMessage = "";
    } else {
      bluetoothSelectorMessage = "Bluetooth action failed";
    }
    bluetoothActionDevice = null;
    bluetoothAction = "";
  }

  function wifiIsSecured(network) {
    return network.security !== "" && network.security !== "--"
      && network.security.toLowerCase() !== "open";
  }

  function connectSelectedWifi() {
    if (wifiNetworks.length === 0 || wifiPendingNetwork !== null)
      return;
    const network = wifiNetworks[Math.min(wifiSelectedIndex, wifiNetworks.length - 1)];
    if (network.active) {
      hideWifiSelector();
      return;
    }

    if (wifiPasswordMode && wifiPassword.length === 0) {
      wifiMessage = "Password required";
      return;
    }

    if (!wifiPasswordMode && wifiIsSecured(network) && !network.known) {
      wifiPasswordMode = true;
      wifiPassword = "";
      wifiMessage = "";
      return;
    }

    wifiPendingNetwork = network;
    wifiConnectionUsedPassword = wifiPasswordMode;
    wifiMessage = "Connecting to " + network.ssid + "…";
    wifiConnectionTimer.restart();

    if (wifiPasswordMode) {
      network.nativeNetwork.connectWithPsk(wifiPassword);
      wifiPassword = "";
      wifiPasswordMode = false;
    } else {
      network.nativeNetwork.connect();
    }
  }

  function failWifiConnection() {
    wifiConnectionTimer.stop();
    const network = wifiPendingNetwork;
    wifiPendingNetwork = null;
    if (network !== null && wifiIsSecured(network)) {
      wifiPasswordMode = true;
      wifiPassword = "";
      wifiMessage = wifiConnectionUsedPassword
        ? "Incorrect password" : "Password required";
    } else {
      wifiMessage = "Unable to connect";
    }
    wifiConnectionUsedPassword = false;
  }

  function toggleUpdateSelector(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    if (updateSelectorVisible && updateTargetMonitor === resolvedTarget)
      hideUpdateSelector();
    else
      showUpdateSelector(resolvedTarget);
  }

  function showUpdateSelector(targetMonitor = "") {
    const resolvedTarget = resolveTargetMonitor(targetMonitor);
    const ownsTransition = beginCenterTransition("updates", resolvedTarget);
    hideAppLauncher();
    hideMediaOverlay();
    hideWifiSelector();
    hideBluetoothSelector();
    hideVolumeOverlay();
    hideBrightnessOverlay();
    hideChromeTabs();
    updateTargetMonitor = resolvedTarget;
    updateSelectorVisible = true;
    finishCenterTransition(ownsTransition);
  }

  function hideUpdateSelector() {
    if (!updateSelectorVisible)
      return;
    const ownsTransition = beginCenterTransition("workspaces");
    updateSelectorVisible = false;
    finishCenterTransition(ownsTransition);
  }

  function startNixUpdate() {
    hideUpdateSelector();
    Quickshell.execDetached(["ghostty", "-e", "quickshell-update-installer"]);
  }

  function refreshNixStatus() {
    if (!nixStatusProcess.running)
      nixStatusProcess.running = true;
  }

  function forceNixStatus() {
    if (!nixForceProcess.running) {
      nixChecking = true;
      nixForceProcess.running = true;
    }
  }

  function parseNixStatus(text) {
    try {
      const status = JSON.parse(text.trim());
      if (Array.isArray(status.updates)) {
        root.nixUpdates = status.updates;
        root.nixIcon = status.hasUpdates ? "" : "";
        root.nixTooltip = status.hasUpdates
          ? status.updates.map(update => update.name + ": " + update.date).join("\n")
          : status.message || "System is up to date";
      } else {
        // Compatibility with the preserved Waybar helper cache format.
        root.nixIcon = status.alt === "has-updates" ? "" : "";
        root.nixTooltip = status.tooltip || "System is up to date";
        const lines = status.alt === "has-updates"
          ? root.nixTooltip.split("\n").filter(line => line.trim() !== "") : [];
        root.nixUpdates = lines.map(line => {
          const separator = line.lastIndexOf(": ");
          return separator >= 0
            ? { "name": line.slice(0, separator), "date": line.slice(separator + 2) }
            : { "name": line, "date": "" };
        });
      }
    } catch (error) {
      root.nixUpdates = [];
      root.nixTooltip = "Unable to check for updates";
    }
    root.nixChecking = false;
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }

  Process {
    id: systemStatsProcess
    command: ["quickshell-system-stats"]
    running: true

    stdout: SplitParser {
      onRead: data => {
        try {
          const stats = JSON.parse(data);
          if (stats.error !== undefined) {
            console.warn("System telemetry error:", stats.error);
            return;
          }
          root.cpuUsage = stats.cpu;
          root.memoryUsage = stats.memory;
          root.diskUsage = stats.disk;
          if (!root.brightnessOverlayVisible)
            root.brightness = stats.brightness;
        } catch (error) {
          console.warn("Unable to parse system stats:", error);
        }
      }
    }
  }

  Connections {
    target: DesktopEntries.applications

    function onValuesChanged() {
      root.rebuildAppCatalog();
    }
  }

  Connections {
    target: Hyprland.toplevels

    function onValuesChanged() {
      root.appToplevelRevision++;
    }
  }

  Connections {
    target: root.mprisPlayer

    function onPostTrackChanged() {
      if (root.mprisInitialized)
        root.showMediaOverlay();
    }
  }

  Connections {
    target: root.wifiPendingNetwork !== null
      ? root.wifiPendingNetwork.nativeNetwork : null

    function onConnectedChanged() {
      if (root.wifiPendingNetwork !== null
          && root.wifiPendingNetwork.nativeNetwork.connected) {
        wifiConnectionTimer.stop();
        root.wifiPendingNetwork = null;
        root.wifiConnectionUsedPassword = false;
        root.hideWifiSelector();
      }
    }

    function onConnectionFailed(reason) {
      root.failWifiConnection();
    }
  }

  Connections {
    target: root.bluetoothActionDevice

    function onConnectedChanged() {
      if (root.bluetoothActionDevice === null)
        return;
      if (root.bluetoothAction === "connect" && root.bluetoothActionDevice.connected)
        root.finishBluetoothAction(true);
      else if (root.bluetoothAction === "disconnect"
          && !root.bluetoothActionDevice.connected)
        root.finishBluetoothAction(true);
    }

    function onPairedChanged() {
      if (root.bluetoothAction === "pair" && root.bluetoothActionDevice !== null
          && root.bluetoothActionDevice.paired)
        root.finishBluetoothAction(true);
    }
  }

  Timer {
    id: wifiScanTimer
    interval: 5000
    onTriggered: root.stopWifiScan()
  }

  Timer {
    id: wifiConnectionTimer
    interval: 20000
    onTriggered: root.failWifiConnection()
  }

  Timer {
    id: bluetoothScanTimer
    interval: 5000
    onTriggered: root.stopBluetoothDiscovery()
  }

  Timer {
    id: bluetoothActionTimer
    interval: 20000
    onTriggered: root.finishBluetoothAction(false)
  }

  Process {
    id: chromeTabsProcess
    command: ["quickshell-chrome-tabs", "list"]

    stdout: StdioCollector {
      onStreamFinished: root.parseChromeTabsResponse(text)
    }
  }

  // Give the compositor one frame to release the layer-shell exclusive
  // keyboard grab before Chrome requests focus for the selected window.
  Timer {
    id: chromeTabsActivationDelay
    interval: 50
    repeat: false
    onTriggered: chromeTabsActionProcess.exec([
      "quickshell-chrome-tabs", root.chromeTabsAction,
      root.chromeTabsActionTabId
    ])
  }

  Process {
    id: chromeTabsActionProcess

    stdout: StdioCollector {
      onStreamFinished: root.parseChromeTabActionResponse(text)
    }
  }

  Process {
    id: brightnessRefreshProcess

    stdout: StdioCollector {
      onStreamFinished: {
        const fields = text.trim().split(",");
        if (fields.length >= 4)
          root.brightness = parseInt(fields[3].replace("%", ""), 10);
      }
    }
  }

  Process {
    id: gpuProcess
    command: ["quickshell-gpu-monitor"]
    running: true

    stdout: SplitParser {
      onRead: data => {
        try {
          const gpu = JSON.parse(data);
          root.gpuText = gpu.text || "--";
          root.gpuTooltip = gpu.tooltip || "GPU data unavailable";
        } catch (error) {
          console.warn("Unable to parse GPU data:", error);
        }
      }
    }
  }

  Process {
    id: weatherProcess
    command: ["quickshell-weather"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const weather = JSON.parse(text.trim());
          root.weatherText = (weather.text || "--") + "°";
          root.weatherTooltip = (weather.tooltip || "Weather unavailable")
            .replace(/<[^>]*>/g, "");
        } catch (error) {
          root.weatherTooltip = "Unable to retrieve weather";
        }
      }
    }
  }

  Timer {
    interval: 3600000
    running: true
    repeat: true
    onTriggered: {
      if (!weatherProcess.running)
        weatherProcess.running = true;
    }
  }

  Process {
    id: nixStatusProcess
    command: ["quickshell-update-checker"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.parseNixStatus(text)
    }
  }

  Process {
    id: nixForceProcess
    command: ["quickshell-update-checker", "force"]
    stdout: StdioCollector {
      onStreamFinished: root.parseNixStatus(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    onTriggered: root.mprisInitialized = true
  }

  Timer {
    id: mediaOverlayTimer
    interval: 4000
    onTriggered: root.hideMediaOverlay()
  }

  Timer {
    id: volumeOverlayTimer
    interval: 2000
    onTriggered: root.hideVolumeOverlay()
  }

  Timer {
    id: brightnessOverlayTimer
    interval: 2000
    onTriggered: root.hideBrightnessOverlay()
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refreshNixStatus()
  }

  IpcHandler {
    target: "topbar"

    function refreshNix() {
      root.refreshNixStatus();
    }

    function mediaPlayPause() {
      root.mediaPlayPause();
    }

    function mediaNext() {
      root.mediaNext();
    }

    function mediaPrevious() {
      root.mediaPrevious();
    }

    function volumeUp() {
      root.volumeUp();
    }

    function volumeDown() {
      root.volumeDown();
    }

    function toggleAudioMute() {
      root.toggleAudioMute();
    }

    function showVolume() {
      root.showVolumeOverlay();
    }

    function showBrightness() {
      root.showBrightnessOverlay();
    }

    function toggleWifi() {
      root.toggleWifiSelector();
    }

    function toggleBluetooth() {
      root.toggleBluetoothSelector();
    }

    function toggleUpdates() {
      root.toggleUpdateSelector();
    }

    function toggleLauncher() {
      root.toggleAppLauncher();
    }

    function toggleChromeTabs() {
      root.toggleChromeTabs();
    }
  }
}
