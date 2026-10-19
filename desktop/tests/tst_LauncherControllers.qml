import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property var events: []
  property var apps: null
  property var appView: null
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
    if (appComponent.status !== Component.Ready) {
      console.error(appComponent.errorString());
      Qt.callLater(() => Qt.exit(1));
      return;
    }
    apps = appComponent.createObject(fixture, {applications: [], toplevels: []});
    apps.closeRequested.connect(() => fixture.events.push("close-app"));
    const views = [
      {name: "appView", path: "AppLauncher.qml", controller: apps},
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
      fixture[view.name].height = Qt.binding(() => fixture[view.name].implicitHeight);
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
      for (const view of [appView, audioView]) {
        view.enabled = false;
        view.visible = false;
      }
    }
    function entry(name) {
      return {id: name + ".desktop", name: name, noDisplay: false, genericName: "",
        keywords: [], comment: "", startupClass: "", icon: "application-x-executable", actions: [],
        execute: () => fixture.events.push("launch-" + name)};
    }
    function setResultCount(count) {
      const names = Array.from({length: count}, (_, index) => "Result " + String(index).padStart(2, "0"));
      apps.applications = names.map(entry);
    }
    function init() {
      fixture.events = [];
      apps.query = "";
      apps.applications = [entry("Terminal"), entry("Éditeur")];
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
    function test_result_height_is_content_sized_and_capped() {
      const view = appView;
      const list = findChild(view, "appResults");
      for (const count of [0, 1, 2, 8, 9, 30, 2, 0]) {
        setResultCount(count);
        const expected = count === 0 ? 114 : Math.min(398, 56 + count * 42);
        compare(view.implicitHeight, expected);
        compare(view.height, expected);
        compare(list.height, expected - 56);
      }
    }
    function test_filtering_after_scrolling_keeps_selection_visible() {
      const view = appView;
      const list = findChild(view, "appResults");
      const field = findChild(view, "appSearchInput");
      setResultCount(30);
      view.visible = true; view.enabled = true;
      tryCompare(field, "activeFocus", true);
      view.controller.selectedIndex = 29;
      tryVerify(() => list.currentItem !== null && list.contentY > list.originY);
      verify(list.currentItem.y + list.currentItem.height <= list.contentY + list.height + 0.5);
      view.controller.setQuery("Result 09");
      compare(view.results.length, 1);
      compare(view.height, 98);
      tryCompare(list, "currentIndex", 0);
      tryVerify(() => list.currentItem !== null && Math.abs(list.contentY - list.originY) < 0.5);
      verify(field.activeFocus);
      view.controller.setQuery("");
      compare(view.height, 398);
      view.enabled = false; view.visible = false;
    }
    function test_empty_message_fits() {
      const view = appView;
      view.width = 340;
      view.visible = true;
      view.controller.setQuery("no-such-result");
      const empty = findChild(view, "appEmptyState");
      verify(empty.visible);
      compare(empty.y, 48);
      verify(empty.implicitHeight <= empty.height - 16);
      verify(empty.y + empty.height <= view.height - 8);
      view.width = 480;
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
    function test_views_receive_only_controller_and_request_close() {
      const view = appView;
      fixture.events = [];
      view.visible = true; view.enabled = true;
      const field = findChild(view, "appSearchInput");
      field.forceActiveFocus(); wait(10);
      verify(field.activeFocus);
      keyClick(Qt.Key_Down);
      compare(view.controller.selectedIndex, 1);
      keyClick(Qt.Key_Escape);
      compare(fixture.events.join(","), "close-view");
      view.enabled = false; view.visible = false;
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
