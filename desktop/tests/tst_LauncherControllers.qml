import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var events: []
  property var apps: null
  property var tabs: null
  property var appView: null
  property var tabView: null
  property var audioView: null
  property bool ready: false

  Component.onCompleted: {
    if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"
        || !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")) {
      Qt.callLater(() => Qt.exit(1));
      return;
    }
    const directory = "file://" + Quickshell.shellDir + "/../features/launchers/";
    const appComponent = Qt.createComponent(directory + "AppLauncherController.qml");
    const tabComponent = Qt.createComponent(directory + "ChromeTabsController.qml");
    if (appComponent.status !== Component.Ready || tabComponent.status !== Component.Ready) {
      console.error(appComponent.errorString(), tabComponent.errorString());
      Qt.callLater(() => Qt.exit(1));
      return;
    }
    apps = appComponent.createObject(fixture, {applications: [], toplevels: []});
    tabs = tabComponent.createObject(fixture, {toplevels: []});
    apps.closeRequested.connect(() => fixture.events.push("close-app"));
    tabs.closeRequested.connect(() => fixture.events.push("close-tabs"));
    const views = [
      {name: "appView", path: "AppLauncher.qml", controller: apps},
      {name: "tabView", path: "ChromeTabsLauncher.qml", controller: tabs},
      {name: "audioView", path: "../audio/AudioSelector.qml", controller: audioMock}
    ];
    for (const view of views) {
      const component = Qt.createComponent(directory + view.path);
      if (component.status !== Component.Ready) {
        console.error(component.errorString());
        Qt.callLater(() => Qt.exit(1));
        return;
      }
      fixture[view.name] = component.createObject(window.contentItem,
        {controller: view.controller, width: 480, height: 398, visible: false, enabled: false});
      fixture[view.name].closeRequested.connect(() => fixture.events.push("close-view"));
    }
    ready = true;
  }

  Window { id: window; width: 480; height: 398; visible: true }
  QtObject {
    id: audioMock
    property var outputs: [{name: "speakers", nickname: "Speakers", isSink: true, ready: true}]
    property var inputs: [{name: "mic", nickname: "Microphone", isSink: false, ready: true}]
    readonly property var sink: outputs[0]
    readonly property var microphoneSource: inputs[0]
    function deviceLabel(node) { return node.nickname; }
    function selectDevice(node) { fixture.events.push("audio-" + node.name); }
  }

  TestResult { id: results }
  TestCase {
    name: "LauncherControllers"
    when: fixture.ready
    function cleanupTestCase() {
      console.log("LauncherControllers: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      for (const view of [appView, tabView, audioView]) {
        view.enabled = false;
        view.visible = false;
      }
    }
    function entry(name) {
      return {id: name + ".desktop", name: name, noDisplay: false, genericName: "",
        keywords: [], comment: "", startupClass: "", icon: "application-x-executable", actions: [],
        execute: () => fixture.events.push("launch-" + name)};
    }
    function init() {
      fixture.events = [];
      apps.query = "";
      apps.applications = [entry("Terminal"), entry("Éditeur")];
      tabs.query = "";
      tabs.action = "";
      tabs.actionTabId = "";
      tabs.actionTab = null;
      tabs.actionToplevel = null;
      tabs.parseResponse(JSON.stringify({ok: true, tabs: [
        {id: "one", title: "Documentation", url: "https://example.org/docs", active: false, pinned: false, audible: false},
        {id: "two", title: "Mail", url: "https://example.org/mail", active: false, pinned: false, audible: false}
      ]}));
    }
    function test_catalog_query_and_wrapped_selection() {
      compare(apps.results.length, 2);
      apps.moveSelection(-1);
      compare(apps.selectedIndex, 1);
      apps.setQuery("editeur");
      compare(apps.results.length, 1);
      compare(apps.results[0].entry.name, "Éditeur");
      compare(apps.selectedIndex, 0);
      apps.setQuery("impossible");
      compare(apps.results.length, 0);
      apps.moveSelection(1);
      compare(apps.selectedIndex, 0);
    }
    function test_catalog_filters_hidden_entries() {
      const hidden = entry("Hidden"); hidden.noDisplay = true;
      apps.applications = [hidden, entry("Visible"), entry("")];
      compare(apps.results.length, 1);
      compare(apps.results[0].entry.name, "Visible");
    }
    function test_close_before_launch_and_new_window_action() {
      apps.setQuery("terminal");
      apps.launchSelected();
      compare(fixture.events.join(","), "close-app,launch-Terminal");
      fixture.events = [];
      const app = entry("Browser");
      app.actions = [{id: "new-window", name: "New window",
        execute: () => fixture.events.push("new-window")}];
      apps.applications = [app]; apps.query = "";
      apps.launchSelected(0, true);
      compare(fixture.events.join(","), "close-app,new-window");
    }
    function test_chrome_filter_and_response_failure() {
      compare(tabs.results.length, 2);
      tabs.setQuery("mail");
      compare(tabs.results[0].tab.id, "two");
      tabs.parseResponse("invalid JSON");
      compare(tabs.results.length, 0);
      compare(tabs.message, "Unable to read Chrome tabs");
      verify(!tabs.loading);
    }
    function test_chrome_close_result_preserves_bounded_selection() {
      tabs.selectedIndex = 1;
      tabs.action = "close"; tabs.actionTabId = "two";
      tabs.parseActionResponse('{"ok":true}');
      compare(tabs.results.length, 1);
      compare(tabs.results[0].tab.id, "one");
      compare(tabs.selectedIndex, 0);
      verify(!tabs.actionPending);
      compare(fixture.events.length, 0);
    }
    function test_chrome_activation_requests_shell_close() {
      tabs.action = "activate"; tabs.actionTab = tabs.results[0].tab;
      tabs.parseActionResponse('{"ok":true}');
      compare(fixture.events.join(","), "close-tabs");
      verify(!tabs.actionPending);
      wait(0);
    }
    function test_views_receive_only_controller_and_request_close() {
      for (const view of [appView, tabView]) {
        fixture.events = [];
        view.visible = true; view.enabled = true;
        const field = findChild(view, view === appView ? "appSearchInput" : "tabSearchInput");
        field.forceActiveFocus(); wait(10);
        verify(field.activeFocus);
        keyClick(Qt.Key_Down);
        compare(view.controller.selectedIndex, 1);
        keyClick(Qt.Key_Escape);
        compare(fixture.events.join(","), "close-view");
        view.enabled = false; view.visible = false;
      }
    }
    function test_audio_view_keeps_keyboard_selection_and_close_contract() {
      audioView.visible = true; audioView.enabled = true;
      audioView.forceActiveFocus(); wait(10);
      compare(audioView.selectedKey, "speakers");
      keyClick(Qt.Key_Tab);
      compare(audioView.selectedKey, "mic");
      keyClick(Qt.Key_Return);
      compare(fixture.events.join(","), "audio-mic");
      keyClick(Qt.Key_Escape);
      compare(fixture.events.join(","), "audio-mic,close-view");
    }
  }
}
