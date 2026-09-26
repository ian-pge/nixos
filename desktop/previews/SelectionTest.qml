import Quickshell
import QtQuick
import QtTest

import "../ui/Theme.js" as Theme
import "../features/calendar/Calendar.js" as Calendar
import "../features/audio"
import "../features/calendar"
import "../features/launchers"
import "../ui"

// Explicit offscreen UI test; all actions use fakes, never launch real apps,
// change the audio route, or make weather/network requests.
ShellRoot {
  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") Qt.exit(1);
  }
  QtObject {
    id: weatherData
    property var days: ({})
    property string locationText: "Paris"
    property string updateText: "Test"
    property bool loading: false
    property bool locationSearchOpen: false
    property string locationQuery: "Paris"
    property string locationSearchError: ""
    property bool searchingLocations: false
    property var locationResults: [
      {name: "Paris", region: "Île-de-France", country: "France"},
      {name: "Paris", region: "Texas", country: "États-Unis"}]
    property var chosen: null
    function setLocationQuery(value) { locationQuery = value; }
    function chooseLocation(value) { chosen = value; }
    function openLocationSearch() { locationSearchOpen = true; }
    function closeLocationSearch() { locationSearchOpen = false; }
  }
  QtObject {
    id: appController
    property var results: [
      {entry: {name: "Application A", icon: "application-x-executable", genericName: "Test", comment: ""}},
      {entry: {name: "Application B", icon: "application-x-executable", genericName: "Test", comment: ""}}]
    property string query: ""
    property int selectedIndex: 0
    property int toplevelRevision: 0
    property int launched: -1
    function toplevelFor(entry) { return null; }
    function setQuery(value) { query = value; }
    function moveSelection(delta) { selectedIndex = (selectedIndex + delta + 2) % 2; }
    function launchSelected(index, detached) { launched = index; }
  }
  QtObject {
    id: tabController
    property var results: [
      {tab: {title: "Onglet A", url: "https://example.test/a", active: true, pinned: false}},
      {tab: {title: "Onglet B", url: "https://example.test/b", active: false, pinned: false}}]
    property var catalog: results
    property string query: ""
    property int selectedIndex: 0
    property bool loading: false
    property bool actionPending: false
    property string message: ""
    property int activated: -1
    function setQuery(value) { query = value; }
    function moveSelection(delta) { selectedIndex = (selectedIndex + delta + 2) % 2; }
    function activateSelected() { activated = selectedIndex; }
    function closeSelected() {}
    function requestTabs() {}
  }
  QtObject {
    id: audioController
    property var outputs: [{name: "speaker", ready: true, isSink: true}]
    property var inputs: [{name: "mic", ready: true, isSink: false}]
    property var sink: outputs[0]
    property var microphoneSource: inputs[0]
    property var selectedAudio: null
    function deviceLabel(node) { return node.name; }
    function selectDevice(node) { selectedAudio = node; }
  }
  QtObject {
    id: state
    property var weather: weatherData
    property date today: Calendar.localDate(2026, 8, 23)
    property int year: 2026
    property int month: 8
    property string selectedDate: "2026-09-24"
    property bool detailsOpen: false
    function moveDay(delta) {
      const day = Calendar.dateFromKey(selectedDate);
      day.setDate(day.getDate() + delta);
      selectedDate = Calendar.dateKey(day);
    }
    function moveMonth(delta) { month += delta; }
    function selectDate(value, details) { selectedDate = value; detailsOpen = details === true; }
    function goToday() { selectedDate = "2026-09-23"; }
    function hideCalendar() {}
  }
  Window {
    id: testWindow
    visible: true
    width: 1000; height: 1000
    AppLauncher { id: apps; width: 480; height: implicitHeight; controller: appController }
    ChromeTabsLauncher { id: tabs; x: 500; width: 480; height: implicitHeight; controller: tabController }
    WeatherLocationSelector { id: cities; y: 415; width: 430; height: implicitHeight; weather: weatherData }
    AudioSelector { id: audio; y: 650; width: 480; height: implicitHeight; controller: audioController }
    CalendarPanel { id: calendar; x: 500; y: 430; width: 434; height: implicitHeight; controller: state }
  }
  TestResult { id: results }
  TestCase {
    name: "GlassSelections"
    when: testWindow.visible
    function initTestCase() { wait(250); }
    function init() {
      GlassState.enabled = true;
      appController.selectedIndex = 0;
      tabController.selectedIndex = 0;
      appController.launched = -1;
      tabController.activated = -1;
      audioController.selectedAudio = null;
      cities.selectedIndex = 0;
      weatherData.chosen = null;
      weatherData.days = ({});
      audio.selectedKey = "speaker";
      state.selectedDate = "2026-09-24";
      state.detailsOpen = false;
      wait(180);
    }
    function cleanupTestCase() {
      console.log("GlassSelections: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount > 0 ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function surface(item, name) { const result = findChild(item, name); verify(result !== null, name); return result; }
    function checkTint(item, name, accent) {
      const target = surface(item, name);
      compare(target.color, Qt.alpha(accent, 0.20));
      compare(target.border.width, 0);
      verify(target.color.a < 0.25);
    }
    function test_translucent_selections() {
      checkTint(apps, "appSelection0", Theme.sideApplications);
      checkTint(tabs, "tabSelection0", Theme.sideApplications);
      checkTint(cities, "weatherSelection0", Theme.sideWeather);
      checkTint(audio, "audioSelection-speaker", Theme.sideVolume);
      checkTint(calendar, "2026-09-24", Theme.calendarSelected);
      compare(surface(apps, "appSelection1").color.a, 0);
      compare(surface(cities, "weatherSelection1").color.a, 0);
      compare(surface(apps, "appIconFrame0").color, Qt.alpha(Theme.sideApplications, 0.08));
      compare(surface(apps, "appIconFrame1").color, Qt.alpha(Theme.foreground, 0.04));
      compare(surface(tabs, "tabIconFrame0").color, Qt.alpha(Theme.sideApplications, 0.08));
      compare(surface(calendar, "2026-09-23").color, Qt.alpha(Theme.sideWeather, 0.20));
      compare(surface(calendar, "2026-09-23").color.a, surface(calendar, "2026-09-24").color.a);
    }
    function test_keyboard_selection_and_action() {
      surface(apps, "appSearchInput").forceActiveFocus();
      keyClick(Qt.Key_Down);
      compare(appController.selectedIndex, 1);
      wait(180);
      checkTint(apps, "appSelection1", Theme.sideApplications);
      compare(surface(apps, "appSelection0").color.a, 0);
      keyClick(Qt.Key_Return);
      compare(appController.launched, 1);

      surface(tabs, "tabSearchInput").forceActiveFocus();
      keyClick(Qt.Key_Down);
      compare(tabController.selectedIndex, 1);
      keyClick(Qt.Key_Return);
      compare(tabController.activated, 1);

      cities.focusSearch();
      keyClick(Qt.Key_Down);
      compare(cities.selectedIndex, 1);
      keyClick(Qt.Key_Return);
      compare(weatherData.chosen.region, "Texas");

      audio.forceActiveFocus();
      keyClick(Qt.Key_Down);
      compare(audio.selectedKey, "mic");
      keyClick(Qt.Key_Return);
      compare(audioController.selectedAudio.name, "mic");

      calendar.forceActiveFocus();
      keyClick(Qt.Key_Right);
      compare(state.selectedDate, "2026-09-25");
      wait(180);
      checkTint(calendar, "2026-09-25", Theme.calendarSelected);
    }
    function test_weather_hourly_details_keep_the_glass_visible() {
      weatherData.days = ({"2026-09-24": {
        code: 3, temperatureMinC: 10, temperatureMaxC: 18,
        hours: Array.from({length: 12}, (_, i) => ({
          time: String(i).padStart(2, "0") + ":00", code: 3,
          temperatureC: 15, apparentTemperatureC: 14,
          precipitationProbability: 0, precipitationMm: 0,
          windKmh: 10, gustsKmh: 20}))}});
      calendar.forceActiveFocus();
      keyClick(Qt.Key_Return);
      verify(state.detailsOpen);
      const details = surface(calendar, "dayDetails");
      verify(details.visible);
      wait(50);
      compare(surface(details, "weatherHour0").color, Qt.alpha(Theme.foreground, 0.04));
      compare(surface(details, "weatherHour1").color.a, 0);
      compare(surface(details, "weatherHour0").border.width, 0);
      keyClick(Qt.Key_J);
      verify(surface(details, "weatherHours").contentY > 0);
      GlassState.enabled = false;
      compare(surface(details, "weatherHour2").color, Theme.surface);
      GlassState.enabled = true;
      compare(surface(details, "weatherHour2").color, Qt.alpha(Theme.foreground, 0.04));
      keyClick(Qt.Key_Escape);
      verify(!state.detailsOpen);
      wait(180);
      checkTint(calendar, "2026-09-24", Theme.calendarSelected);
    }
    function test_opaque_fallback_and_restore() {
      GlassState.enabled = false;
      wait(180);
      compare(surface(apps, "appSelection0").color, Theme.surfaceRaised);
      compare(surface(tabs, "tabSelection0").color, Theme.surfaceRaised);
      compare(surface(cities, "weatherSelection0").color, Theme.surfaceRaised);
      compare(surface(audio, "audioSelection-speaker").color, Theme.surfaceRaised);
      compare(surface(apps, "appIconFrame0").color, Theme.surfaceSelected);
      compare(surface(apps, "appIconFrame1").color, Theme.surface);
      compare(surface(calendar, "2026-09-24").border.width, 1);
      GlassState.enabled = true;
      wait(180);
      checkTint(apps, "appSelection0", Theme.sideApplications);
      checkTint(calendar, "2026-09-24", Theme.calendarSelected);
    }
  }
}
