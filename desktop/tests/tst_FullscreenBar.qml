import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Real layer surfaces over a fullscreen client, on the harness's private display.
ShellRoot {
  id: fixture
  property var app: null
  property var report: null
  property int queryExit: -1
  property string stage: "initialization"
  QtObject {
    id: notice
    property bool visible: false
    property string targetMonitor: ""
    property var presented: ({appName: "Test", summary: "Background notification", body: "Fictional content", image: "", appIcon: ""})
    function close() { visible = false; }
    function activate() {}
  }
  Process {
    id: query
    stdout: StdioCollector { onStreamFinished: fixture.report = JSON.parse(text) }
    onExited: code => fixture.queryExit = code
  }
  Window {
    id: video
    title: "Fullscreen bar test video"
    width: 800; height: 600
    color: "#305080"
    visible: false
  }
  Component.onCompleted: {
    Quickshell.watchFiles = false;
    if (Quickshell.env("QS_MESSENGER_PRIVATE_DBUS") !== "1") { Qt.exit(1); return; }
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../shell.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    app = component.createObject(fixture, {servicesEnabled: false});
    app.services.bluetooth.nativeDevices = [];
  }
  TestResult { id: results }
  TestCase {
    name: "FullscreenBar"
    when: fixture.app !== null
    function readIpc(command) {
      fixture.report = null;
      fixture.queryExit = -1;
      query.exec(["hyprctl", "-j", command]);
      tryCompare(fixture, "queryExit", 0);
      verify(fixture.report !== null);
      return fixture.report;
    }
    function barLayer(bar) {
      const levels = readIpc("layers")[bar.monitorName].levels;
      for (const level of Object.keys(levels)) {
        const surface = levels[level].find(surface => surface.namespace === "quickshell-top-bar");
        if (surface) return {level: Number(level), alpha: surface.alpha};
      }
      return null;
    }
    function expectRaised(bar) {
      fixture.stage += ": overlay layer";
      tryCompare(bar, "visible", true);
      tryCompare(bar.WlrLayershell, "layer", WlrLayer.Overlay);
      fixture.stage += ": compositor visibility";
      tryVerify(() => {
        const surface = barLayer(bar);
        return surface !== null && surface.level === 3 && surface.alpha > 0.99;
      });
      verify(readIpc("clients").some(client => client.title === video.title && client.fullscreen === 2),
        "Opening the bar must leave the video in fullscreen");
    }
    function initTestCase() {
      tryVerify(() => app.bars.length > 0 && app.bars[0].monitorName !== "");
    }
    function init() {
      fixture.stage = "normal client";
      video.showNormal();
      tryVerify(() => readIpc("clients").some(client => client.title === video.title && client.fullscreen === 0));
      tryCompare(app.bars[0], "fullscreenActive", false);
    }
    function cleanup() {
      if (results.failed) console.error("Fullscreen test failed:", fixture.stage);
      app.coordinator.messenger.hide();
      app.coordinator.close(app.coordinator.mode);
    }
    function toggleWindowMode(mode, expected) {
      fixture.stage = "window mode " + mode + " -> " + expected;
      const client = readIpc("clients").find(client => client.title === video.title);
      // The actual dispatchers used by Cmd+Space and Cmd+Shift+Space.
      Hyprland.dispatch('hl.dsp.window.fullscreen({window="address:' + client.address + '",mode="' + mode + '"})');
      tryVerify(() => readIpc("clients").some(current => current.address === client.address && current.fullscreen === expected));
      tryCompare(app.bars[0], "fullscreenActive", (expected & 2) !== 0);
    }
    function test_maximized_keeps_the_bar_and_widgets_visible() {
      const bar = app.bars[0];
      toggleWindowMode("maximized", 1);
      verify(bar.visible);
      app.coordinator.showVolume(bar.monitorName);
      tryCompare(bar.capsule, "overlayVisible", true);
      app.coordinator.close("volume");
      wait(450);
      verify(bar.visible, "Closing a widget must not hide the bar over a maximized window");
      verify(barLayer(bar) !== null);
      toggleWindowMode("maximized", 0);
      verify(bar.visible);
      toggleWindowMode("maximized", 1);
      toggleWindowMode("fullscreen", 2);
      tryCompare(bar, "visible", false);
      toggleWindowMode("maximized", 1);
      tryCompare(bar, "visible", true);
      toggleWindowMode("fullscreen", 2);
      tryCompare(bar, "visible", false);
      toggleWindowMode("fullscreen", 0);
      tryCompare(bar, "visible", true);
    }
    function test_shortcuts_above_fullscreen_and_hide_after_closing() {
      const bar = app.bars[0], host = bar.capsule.messengerHost;
      try {
        toggleWindowMode("fullscreen", 2);
        tryCompare(bar, "visible", false);
        app.coordinator.showVolume("another-monitor");
        compare(bar.visible, false, "Only the target monitor should reveal its bar");
        app.coordinator.close("volume");
        // These are the same controller calls as the topbar IPC shortcuts.
        for (const mode of ["volume", "brightness", "audio", "launcher"]) {
          fixture.stage = mode;
          if (mode === "volume") app.coordinator.showVolume(bar.monitorName);
          else if (mode === "brightness") app.coordinator.showBrightness(bar.monitorName, false);
          else app.coordinator.toggle(mode, bar.monitorName);
          expectRaised(bar);
          app.coordinator.close(mode);
          fixture.stage = mode + ": closing";
          verify(bar.visible, "Keep the closing animation above the video");
          tryCompare(bar, "visible", false, 1500);
          tryVerify(() => barLayer(bar) === null);
        }
        app.coordinator.messenger.show(bar.monitorName);
        fixture.stage = "chat";
        tryCompare(host, "presented", true);
        expectRaised(bar);
        tryCompare(bar.contentItem.Window, "active", true);
        // An OSD can open and close while the chat stays in front of the video.
        app.coordinator.showVolume(bar.monitorName);
        expectRaised(bar);
        app.coordinator.close("volume");
        wait(450);
        expectRaised(bar);
        app.coordinator.messenger.hide();
        verify(host.presented, "Chat remains raised through its closing morph");
        compare(bar.WlrLayershell.layer, WlrLayer.Overlay);
        tryCompare(host, "presented", false, 1500);
        tryCompare(bar, "visible", false, 1500);
        tryVerify(() => barLayer(bar) === null);
        verify(readIpc("clients").some(client => client.title === video.title && client.fullscreen === 2));
        video.hide();
        tryCompare(bar, "fullscreenActive", false);
        tryCompare(bar, "visible", true);
      } finally {
        app.coordinator.messenger.hide();
        app.coordinator.close(app.coordinator.mode);
      }
    }
    function test_notifications_do_not_reveal_the_fullscreen_bar() {
      const bar = app.bars[0], capsule = bar.capsule;
      toggleWindowMode("fullscreen", 2);
      tryCompare(bar, "visible", false);
      try {
        capsule.services = Object.assign({}, bar.services, {notifications: notice});
        notice.targetMonitor = bar.monitorName;
        notice.visible = true;
        tryCompare(capsule, "notificationActive", true);
        wait(450);
        compare(bar.visible, false, "An unsolicited notification must not reveal the bar over video");
        notice.visible = false;
        compare(bar.visible, false, "Dismissing a hidden notification must not start the reveal delay");
        wait(450);
        compare(bar.visible, false);
      } finally {
        notice.visible = false;
        capsule.services = Qt.binding(() => bar.services);
      }
    }
    function test_special_workspace_video_fullscreen() {
      const bar = app.bars[0], host = bar.capsule.messengerHost;
      const client = readIpc("clients").find(client => client.title === video.title);
      const originalWorkspace = client.workspace.address ?? client.workspace.name;
      const specialName = "special:fullscreen-bar-test";
      function specialVisible() {
        return readIpc("monitors").find(m => m.name === bar.monitorName).specialWorkspace.name === specialName;
      }
      function toggleSpecial() {
        Hyprland.dispatch('hl.dsp.workspace.toggle_special("fullscreen-bar-test")');
      }
      try {
        fixture.stage = "move video into named special workspace";
        Hyprland.dispatch('hl.dsp.window.move({window="address:' + client.address
          + '",workspace="' + specialName + '",follow=false})');
        tryVerify(() => readIpc("clients").some(c => c.address === client.address && c.workspace.name === specialName));
        toggleSpecial();
        tryVerify(specialVisible);
        // A client-requested fullscreen, as when YouTube enters fullscreen.
        fixture.stage = "client-requested fullscreen inside special workspace";
        video.showFullScreen();
        tryVerify(() => readIpc("clients").some(c => c.address === client.address && c.fullscreen === 2));
        tryCompare(bar, "fullscreenActive", true);
        tryCompare(bar, "visible", false);

        app.coordinator.showVolume(bar.monitorName);
        expectRaised(bar);
        app.coordinator.close("volume");
        tryCompare(bar, "visible", false, 1500);
        app.coordinator.messenger.show(bar.monitorName);
        tryCompare(host, "presented", true);
        expectRaised(bar);
        app.coordinator.messenger.hide();
        tryCompare(host, "presented", false, 1500);
        tryCompare(bar, "visible", false, 1500);

        fixture.stage = "hidden special workspace must not hide the normal desktop bar";
        toggleSpecial();
        tryVerify(() => !specialVisible());
        tryCompare(bar, "fullscreenActive", false);
        tryCompare(bar, "visible", true);
        fixture.stage = "reopening special workspace restores fullscreen detection";
        toggleSpecial();
        tryVerify(specialVisible);
        tryCompare(bar, "fullscreenActive", true);
        tryCompare(bar, "visible", false);
        toggleWindowMode("maximized", 1);
        tryCompare(bar, "visible", true);
      } finally {
        app.coordinator.messenger.hide();
        app.coordinator.close(app.coordinator.mode);
        video.showNormal();
        Hyprland.dispatch('hl.dsp.window.move({window="address:' + client.address
          + '",workspace="' + originalWorkspace + '",follow=false})');
        tryVerify(() => readIpc("clients").some(c => c.address === client.address
          && (c.workspace.address ?? c.workspace.name) === originalWorkspace));
        if (specialVisible()) toggleSpecial();
      }
    }
    function cleanupTestCase() {
      if (results.failCount) console.error("Fullscreen failure:", fixture.stage,
        JSON.stringify({fullscreen: app.bars[0].fullscreenActive, surface: barLayer(app.bars[0])}));
      video.hide();
      console.log("FullscreenBar: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
  }
}
