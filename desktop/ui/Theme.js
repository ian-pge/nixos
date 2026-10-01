.pragma library

// Shared sizing for the compact bar, independently of expanded panels.
var barScale = 7 / 6;
function barSize(value) { return Math.round(value * barScale); }
var barIconSize = barSize(14);
// Match the outer edge of a dial (radius 13 + half its 2 px stroke).
var barOutlineWidth = 2 * barScale;
function barOutlineInset() { return (barSize(36) - 28 * barScale) / 2; }
var barSelectionOpacity = 0.16;
function barSelectionInset() { return (barSize(36) - barSize(32)) / 2; }

// Semantic palette: pink is interaction, yellow is persistent/live state.
var action = "#ff33cc";
var state = "#ffcc33";
var error = "#ed8796";

var foreground = "#cad3f5";
var selectedForeground = "#ffffff";
var secondary = "#939ab7";
var inactive = "#6e738d";

var background = "#181926";
var surface = "#24273a";
var surfaceRaised = "#363a4f";
var surfaceSelected = "#494d64";

// Text editing, as in Zed: the cursor override from home_manager/zed/settings.nix
// and the search match colors of Zed's Catppuccin Macchiato theme (30 % alpha).
var textCursor = "#ffcc33";
var searchMatch = "#4d8bd5ca";
var searchCurrentMatch = "#4ded8796";

// Fixed Catppuccin accents shared by side capsules and paired central controls.
var pink = "#f5bde6";
var flamingo = "#f0c6c6";
var teal = "#8bd5ca";
var yellow = "#eed49f";
var sideApplications = "#7dc4e4";
var sideUpdates = "#f5a97f"; // Peach
var sideConnectivity = "#8aadf4"; // Blue: microphone, Wi-Fi, Bluetooth, notifications.
var sideNetwork = sideConnectivity;
var sideBluetooth = sideConnectivity;
var sideNotifications = sideConnectivity;
var sideSystem = "#c6a0f6";
var sideDisk = "#91d7e3"; // Sky
var sideCpu = "#91d7e3";
var sideMemory = "#c6a0f6";
var sideGpu = "#a6da95";
var sideBattery = "#f4dbd6"; // Rosewater
var batteryPluggedIn = "#a6da95";
var sideVolume = yellow;
var sideBrightness = sideVolume;
var sideWeather = teal;
var calendarSelected = "#f5a97f";
var weatherSun = "#a6da95";
var weatherRain = "#ed8796";
var sideDate = "#8bd5ca";
var sideTime = "#ed8796";
// Persistent plan-limit dials; Cmd+R refreshes their shared readings.
var usageAccent = "#b7bdf8";
var keyboardSystem = "#a6da95";

// Messenger typography is independent from the compact top-bar widgets.
var beeperUnread = yellow;
var beeperFont = {
  caption: 14, secondary: 15, control: 16, label: 17, body: 20,
  title: 24, subheading: 28, heading: 30, hero: 38, icon: 28, illustration: 52
};
var beeperSenderColors = [
  sideApplications, sideSystem, sideDisk, "#a6da95",
  pink, yellow, error, sideBluetooth,
  sideCpu, "#b7bdf8", "#ee99a0", "#f0c6c6"
];
var beeperNetworkColors = {
  // Catppuccin Macchiato: Mauve, Green, Sapphire, Blue, Pink and Teal.
  all: sideSystem, whatsapp: "#a6da95", telegram: sideApplications,
  signal: sideBluetooth, instagram: pink, sms: sideDate
};
