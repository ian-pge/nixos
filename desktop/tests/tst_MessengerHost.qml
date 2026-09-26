import QtQuick
import QtTest
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// Run only through messenger-wayland_test.mjs --host: the real layer surface
// and focus grabs belong to its private nested compositor, never the desktop.
ShellRoot {
  id: fixture
  property var panel: null
  property var grab: null
  property var model: null
  property var host: null
  property int captureExitCode: -1
  property bool selectorOpen: false
  property bool competingWindowVisible: false
  property string focusStage: ""
  property bool surfaceFocused: window.contentItem.Window.active
  readonly property bool privateSession: Quickshell.env("QS_MESSENGER_PRIVATE_DBUS") === "1"
    && Quickshell.env("QT_QPA_PLATFORM") === "wayland"
  readonly property string monitor: Hyprland.focusedMonitor?.name
    || Hyprland.monitors.values[0]?.name || ""

  QtObject {
    id: controller
    property var beeperData: fixture.model
    property bool visible: false
    property bool blocked: false
    property string targetMonitor: fixture.monitor
    property int focusSerial: 0
    signal aboutToShow()
    function show() { if (!blocked) { targetMonitor = fixture.monitor; aboutToShow(); visible = true; ++focusSerial; } }
    function hide() { visible = false; }
  }
  FloatingWindow {
    id: otherWindow
    visible: fixture.privateSession && fixture.competingWindowVisible
    implicitWidth: 640; implicitHeight: 480
    title: "Messenger focus fixture"
    color: "#181926"
    TextInput { anchors.fill: parent; focus: true }
  }
  PanelWindow {
    id: window
    visible: fixture.privateSession
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-messenger-host-test"
    WlrLayershell.keyboardFocus: fixture.selectorOpen ? WlrKeyboardFocus.Exclusive
      : fixture.host?.wantsKeyboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
      Region { item: fixture.host?.presented ? fixture.host.surfaceItem : null }
      Region { item: fixture.selectorOpen ? selector : null }
    }
    FocusScope {
      id: selector
      z: 2; x: 20; y: 10; width: 220; height: 36
      visible: fixture.selectorOpen
      onVisibleChanged: if (visible) forceActiveFocus()
      TextInput {
        id: selectorInput; anchors.fill: parent; focus: true
        // Real audio selectors consume Tab to change their selected device.
        Keys.onTabPressed: event => event.accepted = true
      }
    }
  }
  Component.onCompleted: {
    if (!fixture.privateSession) {
      console.error("MessengerHost test requires its private nested Wayland runner");
      Qt.exit(1); return;
    }
    const dataComponent = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperData.qml");
    const hostComponent = Qt.createComponent("file://" + Quickshell.shellDir + "/../shell/MessengerHost.qml");
    if (dataComponent.status !== Component.Ready || hostComponent.status !== Component.Ready) {
      console.error(dataComponent.errorString(), hostComponent.errorString()); Qt.exit(1); return;
    }
    model = dataComponent.createObject(fixture, {demo: true});
    host = hostComponent.createObject(window.contentItem, {
      width: Qt.binding(() => window.width), height: Qt.binding(() => window.height),
      controller: controller, panelWindow: window,
      monitorName: Qt.binding(() => fixture.monitor),
      windowFocused: Qt.binding(() => fixture.surfaceFocused),
      keyboardSelectorActive: Qt.binding(() => fixture.selectorOpen)
    });
    if (!host) { console.error("MessengerHost did not instantiate"); Qt.exit(1); return; }
    host.returnFocusRequested.connect(() => { if (fixture.selectorOpen) selector.forceActiveFocus(); });
    const bubble = host.children.find(item => item.objectName === "beeperBubble");
    bubble.animate = false; bubble.glassEnabled = false;
    panel = bubble.contentItem.children.find(item => typeof item.focusNavigation === "function");
    for (const object of host.data) {
      if (object.toString().includes("HyprlandFocusGrab")) grab = object;
    }
    if (!panel || !grab) { console.error("MessengerHost controls missing"); Qt.exit(1); }
  }
  SignalSpy { id: returnSpy; target: host; signalName: "returnFocusRequested" }
  Process {
    id: photoCapture
    command: [Quickshell.env("BEEPER_TEST_GRIM") || "grim", Quickshell.env("BEEPER_PHOTO_SCREENSHOT")]
    onExited: code => fixture.captureExitCode = code
  }
  TestResult { id: results }
  TestCase {
    name: "MessengerHost"
    when: window.visible && fixture.panel !== null && fixture.grab !== null && fixture.model.messages.length > 0
    function cleanupTestCase() {
      controller.hide();
      console.log("MessengerHost: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName, fixture.focusStage,
      "chat", panel.windowFocused, "grab", grab.active, "photo", host.photoPreviewWindow.visible,
      "photoActive", host.photoPreviewWindow.viewer.Window.active, "other", otherWindow.contentItem.Window.active); }
    function init() {
      controller.blocked = false; fixture.selectorOpen = false;
      fixture.surfaceFocused = Qt.binding(() => window.contentItem.Window.active);
      controller.show();
      model.selectChat("studio"); model.draftText = "";
      panel.closeModal(); panel.closeChatSearch(); panel.focusNavigation();
      tryCompare(host, "active", true);
      tryCompare(host, "windowFocused", true);
      tryCompare(panel, "windowFocused", true);
      wait(30); // Drain the explicit show/focusSerial callLater before user input.
      returnSpy.clear();
      fixture.focusStage = "init";
    }
    function test_surface_and_presentation_follow_target_monitor() {
      verify(host.presented); verify(host.wantsKeyboard);
      compare(host.surfaceItem.objectName, "beeperBubbleSurface");
      verify(host.surfaceItem.width > 0); verify(host.surfaceItem.height > 0);
      controller.targetMonitor = "another-monitor";
      tryCompare(host, "active", false); tryCompare(host, "presented", false);
      verify(!host.wantsKeyboard); verify(!panel.active); verify(!model.viewFocused);
    }
    function test_photo_preview_fills_the_monitor_and_space_restores_the_chat() {
      fixture.focusStage = "open photo";
      const chatWidth = host.surfaceItem.width, chatHeight = host.surfaceItem.height;
      panel.previewAttachment = model.messages.find(message => message.id === "photo").attachments[0];
      panel.openModal("media");
      const preview = host.photoPreviewWindow;
      tryCompare(preview, "visible", true);
      tryCompare(preview, "width", window.screen.width);
      tryCompare(preview, "height", window.screen.height);
      compare(preview.screen, window.screen);
      verify(host.wantsKeyboard, "The chat stays keyboard-capable while the photo owns focus");
      tryCompare(preview.viewer, "activeFocus", true);
      const image = findChild(preview.viewer, "beeperMediaImage");
      tryCompare(image, "status", Image.Ready);
      compare(image.width, preview.width); compare(image.height, preview.height);
      compare(host.surfaceItem.width, chatWidth); compare(host.surfaceItem.height, chatHeight);
      if (Quickshell.env("BEEPER_PHOTO_SCREENSHOT")) {
        wait(150);
        fixture.captureExitCode = -1; photoCapture.running = true;
        tryCompare(fixture, "captureExitCode", 0);
      }
      fixture.focusStage = "space closes photo";
      keyClick(Qt.Key_Space);
      tryCompare(preview, "visible", false);
      compare(panel.modal, ""); verify(host.active);
      fixture.focusStage = "focus returns after photo";
      tryCompare(panel, "windowFocused", true);
      tryCompare(grab, "active", true);
      panel.openModal("media"); tryCompare(preview, "visible", true);
      tryCompare(preview.viewer, "activeFocus", true);
      keyClick(Qt.Key_Escape); tryCompare(preview, "visible", false);
      verify(host.active);
    }
    function test_video_uses_full_monitor_and_space_keeps_the_viewer_open() {
      panel.previewAttachment = {type: "video", srcURL: "file://" + Quickshell.shellDir + "/fixtures/fullscreen-video.mp4", duration: 20};
      panel.openModal("media");
      const preview = host.photoPreviewWindow;
      tryCompare(preview, "visible", true);
      tryCompare(preview.viewer, "activeFocus", true);
      compare(preview.width, window.screen.width); compare(preview.height, window.screen.height);
      const player = findChild(preview.viewer, "beeperMediaPlayer"); verify(player !== null);
      tryCompare(player, "playbackState", MediaPlayer.PlayingState, 3000);
      const output = findChild(preview.viewer, "beeperMediaVideo");
      tryVerify(() => output.sourceRect.width > 0 && output.sourceRect.height > 0);
      compare(output.width, preview.width); compare(output.height, preview.height);
      keyClick(Qt.Key_Space); tryCompare(player, "playbackState", MediaPlayer.PausedState);
      verify(preview.visible); verify(host.wantsKeyboard);
      keyClick(Qt.Key_L); tryVerify(() => player.position >= 5000);
      keyClick(Qt.Key_H); verify(player.position < 5000);
      keyClick(Qt.Key_Escape); tryCompare(preview, "visible", false);
      tryCompare(panel, "windowFocused", true); tryCompare(grab, "active", true);
    }
    function test_blocked_releases_keyboard_and_preserves_draft() {
      panel.compose(); const composer = findChild(host, "beeperComposer");
      composer.text = "Preserve my draft";
      tryCompare(grab, "active", true);
      controller.blocked = true;
      verify(host.active); verify(host.presented);
      verify(!host.wantsKeyboard); verify(!grab.active);
      verify(!panel.active); verify(!panel.windowFocused); verify(!model.viewFocused);
      host.focusMessenger(); verify(!grab.active);
      compare(model.draftText, "Preserve my draft");
      controller.blocked = false;
      tryCompare(panel, "active", true);
      verify(!grab.active, "Unblocking must not take OS focus back");
      compare(model.draftText, "Preserve my draft");
    }
    function test_photo_close_keeps_focus_when_another_application_is_available() {
      fixture.competingWindowVisible = true;
      try {
        controller.hide();
        fixture.focusStage = "focus other application";
        tryCompare(otherWindow.contentItem.Window, "active", true);
        fixture.focusStage = "restore chat from other application";
        controller.show(); tryCompare(panel, "windowFocused", true);
        panel.composer.text = "";
        for (let i = 0; i < 3; ++i) {
          fixture.focusStage = "open photo cycle " + i;
          panel.previewAttachment = model.messages.find(message => message.id === "photo").attachments[0];
          panel.openModal("media");
          tryCompare(host.photoPreviewWindow, "visible", true);
          tryCompare(host.photoPreviewWindow.viewer.Window, "active", true);
          Hyprland.dispatch("hl.dsp.cursor.move({x=4,y=4})");
          wait(30);
          fixture.focusStage = "close photo cycle " + i;
          keyClick(Qt.Key_Space);
          tryCompare(host.photoPreviewWindow, "visible", false);
          wait(250); // Include the compositor's delayed unmap/focus events.
          fixture.focusStage = "settled focus cycle " + i;
          verify(panel.windowFocused, "Closing the photo must keep OS keyboard focus on the chat");
          verify(grab.active); verify(!otherWindow.contentItem.Window.active);
          fixture.focusStage = "Enter after photo cycle " + i;
          keyClick(Qt.Key_Return); verify(panel.composer.activeFocus);
          fixture.focusStage = "type after photo cycle " + i;
          keyClick(Qt.Key_X); compare(model.draftText, "x".repeat(i + 1));
          panel.focusNavigation();
        }
      } finally { fixture.competingWindowVisible = false; }
    }
    function test_selector_returns_to_the_same_composer_without_os_grab() {
      panel.compose(); const composer = findChild(host, "beeperComposer");
      composer.text = "Still composing";
      fixture.selectorOpen = true;
      tryCompare(selectorInput, "activeFocus", true);
      verify(!panel.windowFocused); verify(!model.viewFocused); verify(!grab.active);
      keyClick(Qt.Key_Tab); compare(model.networkFilter, "all");
      verify(selectorInput.activeFocus);
      fixture.selectorOpen = false;
      tryCompare(composer, "activeFocus", true);
      compare(model.draftText, "Still composing");
      verify(!grab.active, "Returning inside the layer surface must not steal OS focus");
    }
    function test_focus_serial_is_explicit_activation_even_with_selector_visible() {
      fixture.selectorOpen = true;
      tryCompare(selectorInput, "activeFocus", true);
      controller.show();
      tryCompare(panel, "activeFocus", true);
      verify(fixture.selectorOpen, "Explicit chat activation keeps the top-bar widget open");
      controller.hide();
      tryCompare(selectorInput, "activeFocus", true);
      tryCompare(returnSpy, "count", 1);
    }
    function test_focus_serial_enters_disconnected_chat_from_selector() {
      const chats = model.chats;
      try {
        fixture.selectorOpen = true;
        tryCompare(selectorInput, "activeFocus", true);
        model.chats = []; model.state = "offline";
        wait(30);
        verify(findChild(host, "beeperConnectionSurface").visible);
        verify(selectorInput.activeFocus, "A passive reconnect must not steal selector focus");
        verify(!panel.windowFocused);
        ++controller.focusSerial;
        tryCompare(findChild(host, "beeperReconnect"), "activeFocus", true);
        verify(panel.windowFocused);
        verify(fixture.selectorOpen, "Explicit activation must not close the selector");

        selector.forceActiveFocus();
        tryCompare(selectorInput, "activeFocus", true);
        model.state = "needs-token";
        wait(30);
        verify(selectorInput.activeFocus);
        ++controller.focusSerial;
        tryCompare(findChild(host, "beeperToken"), "activeFocus", true);
        verify(panel.windowFocused);
      } finally {
        model.chats = chats; model.state = "demo";
        fixture.selectorOpen = false;
      }
    }
    function test_passive_reconnection_does_not_grab_selector_focus() {
      const chats = model.chats;
      try {
        fixture.selectorOpen = true;
        tryCompare(selectorInput, "activeFocus", true);
        model.chats = []; model.state = "offline";
        wait(30);
        verify(selectorInput.activeFocus);
        verify(!panel.windowFocused); verify(!grab.active);
        model.chats = chats; model.state = "demo";
        wait(30);
        verify(selectorInput.activeFocus, "Background recovery must not restore chat focus");
        verify(!panel.windowFocused); verify(!grab.active);
      } finally {
        model.chats = chats; model.state = "demo";
        fixture.selectorOpen = false;
      }
    }
    function test_lost_surface_focus_does_not_restore_on_selector_close() {
      fixture.selectorOpen = true;
      tryCompare(selectorInput, "activeFocus", true);
      fixture.surfaceFocused = false;
      fixture.selectorOpen = false; wait(30);
      verify(!panel.windowFocused); verify(!model.viewFocused); verify(!grab.active);
    }
    function test_native_dialog_and_modal_keep_focus_contract() {
      panel.openModal("help"); wait(0);
      verify(findChild(host, "beeperModalSurface").activeFocus);
      panel.nativeDialogOpened();
      verify(host.nativeDialogOpen); verify(!host.wantsKeyboard);
      verify(!grab.active); verify(!panel.windowFocused); verify(!model.viewFocused);
      panel.nativeDialogClosed();
      tryCompare(findChild(host, "beeperModalSurface"), "activeFocus", true);
      tryCompare(grab, "active", true);
      verify(host.wantsKeyboard);
      keyClick(Qt.Key_Escape); compare(panel.modal, "");
      verify(host.active);
    }
  }
}
