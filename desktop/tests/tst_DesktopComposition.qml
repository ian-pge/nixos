import QtQuick
import QtTest
import Quickshell

// Instantiate the complete production composition only in a private nested
// Wayland session, with helper processes/agents disabled and fictional chat.
ShellRoot {
  id: fixture
  property var app: null
  property string stage: ""
  QtObject {
    id: noticeState
    property bool visible: false
    property string targetMonitor: ""
    property var presented: ({appName: "System", summary: "Task finished", body: "Fictional notification", image: "", appIcon: ""})
    function close() { visible = false; }
    function activate() {}
  }
  Component.onCompleted: {
    if (Quickshell.env("QS_MESSENGER_PRIVATE_DBUS") !== "1"
        || Quickshell.env("QT_QPA_PLATFORM") !== "wayland") { Qt.exit(1); return; }
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../shell.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    app = component.createObject(fixture, {servicesEnabled: false});
  }
  TestResult { id: results }
  TestCase {
    name: "DesktopComposition"
    when: fixture.app !== null
    function cleanupTestCase() {
      console.log("DesktopComposition: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName, fixture.stage); }
    function test_registry_and_real_bar_bindings() {
      wait(150);
      compare(app.coordinator.mode, "workspaces");
      verify(!app.services.system.enabled); verify(!app.services.dictation.enabled);
      verify(!app.services.auth.serviceEnabled); verify(!app.services.updates.autoCheckEnabled);
      verify(!app.services.network.active); verify(!app.services.bluetooth.active);
      verify(app.coordinator.messenger.beeperData.demo);
      tryVerify(() => app.bars.length > 0);
      const capsule = app.bars[0].capsule;
      verify(capsule !== null, "The actual Bar must instantiate its central capsule");
      compare(capsule.services.audio, app.services.audio);
      compare(capsule.coordinator, app.coordinator);
      verify(capsule.messengerHost !== null);
      verify(capsule.width > 0); verify(capsule.width <= capsule.maximumWidth);
      verify(capsule.visible);
    }
    function test_chat_weather_handoff_has_one_material_and_one_endpoint() {
      tryVerify(() => app.bars.length > 0);
      const bar = app.bars[0], capsule = bar.capsule, host = capsule.messengerHost;
      const bubble = findChild(host, "beeperBubble"), animation = findChild(bubble, "beeperBubbleReveal");
      const capsuleGlass = findChild(capsule, "capsuleGlassShape");
      const chatGlass = findChild(bubble, "beeperGlassShape");
      try {
        bubble.animate = false;
        app.coordinator.messenger.show(bar.monitorName);
        compare(bubble.progress, 1);
        bubble.animate = true;
        app.coordinator.open("calendar", bar.monitorName);
        animation.pause();
        verify(capsule.targetHeight > 36);
        compare(bubble.capsuleWidth, capsule.targetWidth);
        compare(bubble.capsuleHeight, capsule.targetHeight);
        compare(capsule.height, capsule.targetHeight);
        for (const progress of [1, 0.6, 0.3, 0.05, 0.002]) {
          bubble.progress = progress;
          verify(bubble.visible); verify(!capsule.drawBackground);
          verify(!capsuleGlass.enabled);
          verify(!(capsuleGlass.enabled && chatGlass.enabled));
          verify(bubble.surfaceItem.height >= capsule.targetHeight);
        }
        bubble.progress = 0; animation.stop();
        verify(!bubble.visible); verify(capsule.drawBackground);
        compare(bubble.surfaceItem.width, capsule.width);
        compare(bubble.surfaceItem.height, capsule.height);
        compare(bubble.surfaceItem.y, capsule.y);
        const settledHeight = capsule.height;
        wait(80); compare(capsule.height, settledHeight, "No old height animation may finish after the handoff");

        // Reopen from weather, then reverse mid-morph toward a different panel.
        app.coordinator.messenger.show(bar.monitorName); animation.pause();
        compare(bubble.capsuleHeight, settledHeight);
        bubble.progress = 0.45;
        const before = bubble.surfaceItem.height, y = bubble.surfaceItem.y;
        app.coordinator.open("wifi", bar.monitorName); animation.pause();
        compare(bubble.surfaceItem.height, before); compare(bubble.surfaceItem.y, y);
        compare(bubble.capsuleHeight, capsule.targetHeight);
        verify(!capsule.drawBackground);
        bubble.progress = 0; animation.stop();
        compare(bubble.surfaceItem.height, capsule.height);
      } finally {
        animation.stop(); bubble.animate = false;
        app.coordinator.messenger.hide(); app.coordinator.close(app.coordinator.mode);
        bubble.animate = true;
      }
    }
    function test_system_notifications_stay_in_bar_without_stealing_chat_focus() {
      tryVerify(() => app.bars.length > 0);
      const bar = app.bars[0], capsule = bar.capsule, host = capsule.messengerHost;
      const services = capsule.services;
      capsule.services = Object.assign({}, services, {notifications: noticeState});
      app.coordinator.services = capsule.services;
      try {
        fixture.stage = "focus chat";
        app.coordinator.messenger.show(bar.monitorName);
        tryCompare(host, "active", true);
        verify(app.services.notifications.suppressChatBanners);
        wait(30); // Let the host's explicit deferred focus request settle.
        const composer = findChild(host, "beeperComposer");
        verify(composer !== null);
        composer.forceActiveFocus();
        tryCompare(composer, "activeFocus", true);
        composer.text = "Keep this draft";
        wait(450);
        const panelWidth = host.surfaceItem.width, panelHeight = host.surfaceItem.height;
        noticeState.targetMonitor = bar.monitorName; noticeState.visible = true;
        fixture.stage = "notification enters";
        tryCompare(capsule, "targetMode", "notification");
        const popup = findChild(capsule, "barNotification");
        tryVerify(() => popup !== null && popup.enabled && popup.opacity > 0.99, 1000);
        fixture.stage = "notification geometry and focus";
        compare(findChild(host, "barNotification"), null);
        compare(capsule.y, bar.barTopInset); verify(capsule.width <= capsule.maximumWidth);
        compare(host.surfaceItem.width, panelWidth); compare(host.surfaceItem.height, panelHeight);
        verify(host.active); verify(composer.activeFocus); compare(composer.text, "Keep this draft");
        compare(capsule.contentOpacity("workspaces"), 0);
        // A volume/brightness request takes the same bar slot, never the chat.
        app.coordinator.showVolume(bar.monitorName);
        fixture.stage = "volume";
        verify(!noticeState.visible); compare(capsule.targetMode, "volume"); verify(host.active);
        noticeState.visible = true;
        app.coordinator.showBrightness(bar.monitorName, false);
        fixture.stage = "brightness";
        verify(!noticeState.visible); compare(capsule.targetMode, "brightness"); verify(host.active);
        app.coordinator.close("brightness");
        wait(250); compare(capsule.contentOpacity("workspaces"), 0);
        verify(composer.activeFocus); compare(composer.text, "Keep this draft");
        app.coordinator.open("audio", bar.monitorName);
        fixture.stage = "audio replacement";
        verify(!host.active); compare(app.coordinator.mode, "audio");
        verify(!app.services.notifications.suppressChatBanners);
        app.coordinator.messenger.show(bar.monitorName);
        compare(app.coordinator.mode, "workspaces"); tryCompare(host, "active", true);
        compare(composer.text, "Keep this draft");
        app.coordinator.open("calendar", bar.monitorName);
        fixture.stage = "calendar replacement";
        verify(!host.active); compare(app.coordinator.mode, "calendar");
        app.coordinator.messenger.show(bar.monitorName);
        compare(app.coordinator.mode, "workspaces"); compare(composer.text, "Keep this draft");
      } finally {
        noticeState.visible = false;
        app.coordinator.messenger.hide();
        app.coordinator.mode = "workspaces";
        capsule.services = Qt.binding(() => app.services);
        app.coordinator.services = Qt.binding(() => app.services);
      }
    }
    function test_scrolling_history_does_not_resize_the_top_bar_or_panel() {
      tryVerify(() => app.bars.length > 0);
      const bar = app.bars[0], capsule = bar.capsule, host = capsule.messengerHost;
      const model = app.coordinator.messenger.beeperData;
      app.coordinator.messenger.show(bar.monitorName);
      tryCompare(host, "active", true); wait(450);
      const width = capsule.width, height = capsule.height;
      const panelWidth = host.surfaceItem.width, panelHeight = host.surfaceItem.height;
      const list = findChild(host, "beeperMessages");
      try {
        for (let i = 0; i < 6; ++i) {
          mouseWheel(list, list.width / 2, list.height / 2, 0, i < 3 ? 120 : -120, Qt.NoButton);
          wait(40);
          compare(capsule.width, width); compare(capsule.height, height);
          compare(host.surfaceItem.width, panelWidth); compare(host.surfaceItem.height, panelHeight);
        }
      } finally { app.coordinator.messenger.hide(); }
    }
  }
}
