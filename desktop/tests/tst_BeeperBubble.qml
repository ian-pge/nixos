import QtQuick
import QtQuick.Shapes
import QtTest
import Quickshell

// Local-only geometry, animation and focus tests. No desktop service graph,
// account, real audio route, notification server or microphone is started.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var bubble: null
  property var panel: null
  property var audioPicker: null
  function create(name, parent, properties) {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../" + name + ".qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return null; }
    return component.createObject(parent, properties);
  }
  Component.onCompleted: {
    beeperData = create("features/messenger/BeeperData", fixture, {demo: true});
    bubble = create("shell/BeeperBubble", window.contentItem, {
      width: Qt.binding(() => window.width), height: Qt.binding(() => window.height),
      sourceWidth: Qt.binding(() => center.width), sourceHeight: Qt.binding(() => center.height),
      expanded: true, animate: false, glassEnabled: false
    });
    panel = create("features/messenger/BeeperPanel", bubble.contentItem, {
      width: Qt.binding(() => bubble.panelWidth), height: Qt.binding(() => bubble.panelHeight),
      beeperData: beeperData, active: Qt.binding(() => bubble.expanded),
      windowFocused: Qt.binding(() => window.active && !!fixture.panel?.activeFocus)
    });
    const volumeIndicator = create("features/audio/VolumeIndicator", center, {
      width: Qt.binding(() => center.width), height: Qt.binding(() => center.height),
      controller: audioState, visible: Qt.binding(() => audioState.volumeOverlayVisible)
    });
    volumeIndicator.adjustRequested.connect(delta => audioState.setVolume(delta));
    create("features/brightness/BrightnessIndicator", center, {
      width: Qt.binding(() => center.width), height: Qt.binding(() => center.height),
      controller: brightnessViewState, visible: Qt.binding(() => audioState.brightnessOverlayVisible)
    });
    audioPicker = create("features/audio/AudioSelector", center, {
      width: Qt.binding(() => center.width), height: Qt.binding(() => center.height),
      controller: audioState, visible: Qt.binding(() => audioState.audioSelectorVisible),
      enabled: Qt.binding(() => audioState.audioSelectorVisible)
    });
    audioPicker.closeRequested.connect(() => audioState.hideAudioSelector());
  }
  QtObject {
    id: brightnessViewState
    function value(monitor) { return audioState.brightness; }
    function icon(monitor) { return "󰃠"; }
  }
  QtObject {
    id: audioState
    property bool audioSelectorVisible: false
    property bool volumeOverlayVisible: false
    property bool brightnessOverlayVisible: false
    property int audioVolume: 50
    readonly property int volume: audioVolume
    property int brightness: 50
    property real volumeStep: 0.05
    property var outputs: [{name: "speakers", description: "Speakers", isSink: true, ready: true}]
    property var inputs: [{name: "mic", description: "Microphone", isSink: false, ready: true}]
    property var sink: outputs[0]
    property var microphoneSource: inputs[0]
    function audioIcon() { return "󰕾"; }
    function brightnessIcon() { return "󰃠"; }
    function icon() { return audioIcon(); }
    function deviceLabel(node) { return node.description; }
    function setVolume(delta) { audioVolume = Math.round(audioVolume + delta * 100); }
    function showVolumeOverlay() { volumeOverlayVisible = true; }
    function changeBrightness(delta) { brightness += delta; brightnessOverlayVisible = true; }
    function hideAudioSelector() { audioSelectorVisible = false; panel.forceActiveFocus(); }
  }
  Window {
    id: window
    width: 1440; height: 1080; visible: true
    Rectangle {
      id: center
      z: 2; y: 10
      width: audioState.volumeOverlayVisible || audioState.brightnessOverlayVisible ? 280 : 434
      height: audioState.audioSelectorVisible ? audioPicker?.implicitHeight || 36 : 36
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }
  TestResult { id: results }
  TestCase {
    name: "BeeperBubble"
    when: window.visible && audioPicker !== null && beeperData.messages.length > 0
    function cleanupTestCase() {
      console.log("BeeperBubble: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function init() {
      bubble.glassEnabled = false;
      bubble.animate = false;
      bubble.expanded = false;
      window.width = 1440; window.height = 1080;
      audioState.volumeOverlayVisible = false; audioState.audioSelectorVisible = false;
      audioState.brightnessOverlayVisible = false;
      bubble.expanded = true;
      beeperData.selectChat("studio"); beeperData.draftText = "";
      // Test setup assigns input.text directly; restore the component's binding
      // before each row, otherwise assigning the same fixture draft emits no edit.
      findChild(panel, "beeperComposer").text = Qt.binding(() => beeperData.draftText);
      panel.closeModal(); panel.closeChatSearch(); panel.focusNavigation(); wait(30);
    }
    function test_centered_in_work_area_with_separate_overlay_geometry() {
      compare(bubble.surfaceItem.width, 1280);
      compare(bubble.surfaceItem.height, 914);
      compare(bubble.surfaceItem.y, 106);
      compare(bubble.surfaceItem.x + bubble.surfaceItem.width / 2, window.width / 2);
      compare(center.y, 10); compare(center.width, 434); compare(center.height, 36);
      verify(bubble.surfaceItem.y > center.y + center.height);
      compare(bubble.originContentOpacity, 0);
    }
    function test_message_shapes_request_native_curve_antialiasing() {
      const list = findChild(panel, "beeperMessages");
      list.positionViewAtIndex(0, ListView.Beginning); wait(30);
      const shape = findChild(list.itemAtIndex(0), "beeperMessageShape");
      compare(shape.preferredRendererType, Shape.CurveRenderer);
      verify(shape.antialiasing);
      if (Quickshell.env("QT_QUICK_BACKEND") !== "software") {
        verify(waitForRendering(shape));
        compare(shape.rendererType, Shape.CurveRenderer);
      }
    }
    function test_capsule_morph_keeps_layout_stable_and_never_resizes_bar() {
      bubble.progress = 0;
      compare(bubble.surfaceItem.width, center.width);
      compare(bubble.surfaceItem.height, center.height);
      compare(bubble.surfaceItem.y, center.y);
      compare(bubble.originContentOpacity, 1);
      let previousWidth = 0, previousHeight = 0;
      let previousOriginOpacity = 1;
      for (const progress of [0.05, 0.2, 0.35, 0.48, 0.6, 0.8, 1]) {
        bubble.progress = progress;
        verify(bubble.surfaceItem.width >= previousWidth);
        verify(bubble.surfaceItem.height >= previousHeight);
        verify(bubble.surfaceItem.width <= 1280); verify(bubble.surfaceItem.height <= 914);
        compare(panel.width, 1280); compare(panel.height, 914);
        compare(center.y, 10); compare(center.width, 434); compare(center.height, 36);
        previousWidth = bubble.surfaceItem.width; previousHeight = bubble.surfaceItem.height;
        verify(bubble.originContentOpacity <= previousOriginOpacity);
        previousOriginOpacity = bubble.originContentOpacity;
      }
      compare(bubble.originContentOpacity, 0);
    }
    function test_source_dimensions_are_captured_at_opening() {
      bubble.expanded = false;
      audioState.audioSelectorVisible = true;
      wait(20);
      const sourceWidth = center.width, sourceHeight = center.height;
      verify(sourceHeight > 36);
      bubble.expanded = true;
      bubble.progress = 0;
      compare(bubble.surfaceItem.width, sourceWidth);
      compare(bubble.surfaceItem.height, sourceHeight);
      bubble.progress = 0.4;
      const x = bubble.surfaceItem.x, y = bubble.surfaceItem.y;
      const width = bubble.surfaceItem.width, height = bubble.surfaceItem.height;
      audioState.audioSelectorVisible = false;
      audioState.showVolumeOverlay();
      wait(0);
      compare(center.width, 280); compare(center.height, 36);
      compare(bubble.surfaceItem.x, x); compare(bubble.surfaceItem.y, y);
      compare(bubble.surfaceItem.width, width); compare(bubble.surfaceItem.height, height);
    }
    function test_close_returns_to_current_capsule_dimensions() {
      audioState.showVolumeOverlay();
      compare(bubble.surfaceItem.width, 1280);
      bubble.expanded = false;
      compare(bubble.progress, 0);
      compare(bubble.surfaceItem.width, 280);
      compare(bubble.surfaceItem.height, 36);
      compare(bubble.surfaceItem.y, center.y);
    }
    function test_small_screen_stays_inside_work_area() {
      window.width = 800; window.height = 720; wait(0);
      compare(bubble.surfaceItem.width, 746);
      compare(bubble.surfaceItem.height, 554);
      compare(bubble.surfaceItem.y, 106);
      verify(bubble.surfaceItem.x >= 0);
      verify(bubble.surfaceItem.y + bubble.surfaceItem.height <= window.height);
    }
    function test_both_directions_start_fast_and_slow_near_the_destination_data() {
      return [{tag: "opening", expanded: true}, {tag: "closing", expanded: false}];
    }
    function test_height_leaves_50_above_and_below_without_old_cap() {
      window.height = 1440; wait(0);
      compare(bubble.tiledWindowHeight, 1374);
      compare(bubble.surfaceItem.height, 1274);
      compare(bubble.surfaceItem.y - bubble.workAreaTop - bubble.windowTopGap, 50);
      compare(window.height - bubble.windowBottomGap - bubble.surfaceItem.y - bubble.surfaceItem.height, 50);
    }
    function test_both_directions_start_fast_and_slow_near_the_destination(data) {
      bubble.expanded = !data.expanded;
      const start = bubble.progress, destination = data.expanded ? 1 : 0;
      bubble.animate = true;
      bubble.expanded = data.expanded;
      const animation = findChild(bubble, "beeperBubbleReveal");
      compare(animation.property, "progress");
      compare(animation.easing.type, Easing.OutCubic);
      compare(animation.duration, bubble.animationDuration);
      // Keep the real animation/easing but stretch this timing probe so a busy
      // nested compositor cannot skip its early sample within one frame wait.
      animation.stop(); animation.duration = 1440; animation.start();
      wait(180);
      const earlyTravel = Math.abs(bubble.progress - start);
      verify(earlyTravel > 0.2 && earlyTravel < 1,
        "The early movement must be fast in both directions: " + earlyTravel);
      wait(900);
      const finalQuarterTravel = Math.abs(destination - bubble.progress);
      verify(earlyTravel > finalQuarterTravel * 3,
        "The final quarter must travel less than the first, including while closing");
      // QtTest's numeric compare is fuzzy: near-zero is not the hidden endpoint.
      tryVerify(() => bubble.progress === destination && !bubble.animating, 1000);
      compare(bubble.visible, data.expanded);
    }
    function test_native_animation_reverses_with_remaining_duration() {
      bubble.expanded = false;
      bubble.animate = true;
      bubble.expanded = true;
      const animation = findChild(bubble, "beeperBubbleReveal");
      compare(animation.easing.type, Easing.OutCubic);
      compare(animation.duration, bubble.animationDuration);
      wait(90);
      const progress = bubble.progress;
      verify(progress > 0 && progress < 1);
      bubble.expanded = false;
      compare(bubble.progress, progress);
      compare(animation.from, progress); compare(animation.to, 0);
      fuzzyCompare(animation.duration, bubble.animationDuration * progress, 1);
      verify(!bubble.contentItem.enabled); verify(bubble.visible);
      wait(20);
      verify(bubble.progress < progress);
      tryCompare(bubble, "visible", false, 800);
      compare(bubble.progress, 0);
    }
    function test_close_preserves_pixels_and_endpoints_while_osd_changes() {
      bubble.animate = true;
      bubble.expanded = false;
      compare(bubble.progress, 1); verify(bubble.visible); verify(!bubble.contentItem.enabled);
      compare(bubble.contentItem.opacity, 1);
      // Snapshot a supported direct-progress preview frame. The OSD contract
      // must not depend on how many frames a compositor delivered during wait().
      findChild(bubble, "beeperBubbleReveal").pause();
      bubble.progress = 0.55;
      verify(bubble.contentItem.opacity > 0);
      const capsuleWidth = bubble.capsuleWidth, capsuleHeight = bubble.capsuleHeight;
      audioState.showVolumeOverlay();
      compare(center.width, 280);
      compare(bubble.capsuleWidth, capsuleWidth); compare(bubble.capsuleHeight, capsuleHeight);
      const progress = bubble.progress, width = bubble.surfaceItem.width, height = bubble.surfaceItem.height;
      bubble.expanded = true;
      compare(bubble.progress, progress);
      compare(bubble.surfaceItem.width, width); compare(bubble.surfaceItem.height, height);
      compare(bubble.capsuleWidth, capsuleWidth); compare(bubble.capsuleHeight, capsuleHeight);
      tryCompare(bubble, "progress", 1, 800);
    }
    function test_glass_material_survives_until_the_last_closing_frame() {
      bubble.glassEnabled = true;
      const glass = findChild(bubble, "beeperGlassShape");
      verify(glass.enabled); verify(glass.visible);
      bubble.animate = true;
      bubble.expanded = false;
      verify(bubble.visible); verify(glass.enabled);
      verify(!bubble.contentItem.enabled, "Closing must stop input, not rendering");
      wait(100);
      verify(bubble.animating); verify(bubble.progress > 0);
      verify(glass.enabled); verify(glass.visible);
      compare(glass.width, bubble.surfaceItem.width);
      compare(glass.height, bubble.surfaceItem.height);
      tryCompare(bubble, "visible", false, 1000);
      verify(!glass.visible); verify(!glass.enabled);
      bubble.glassEnabled = false;
    }
    function test_interrupted_close_reverses_without_jump() {
      bubble.animate = true;
      bubble.expanded = false; wait(110);
      verify(bubble.visible); verify(!bubble.contentItem.enabled);
      verify(bubble.progress > 0 && bubble.progress < 1);
      const before = bubble.progress;
      const widthBefore = bubble.surfaceItem.width, heightBefore = bubble.surfaceItem.height;
      bubble.expanded = true;
      fuzzyCompare(bubble.progress, before, 0.01);
      fuzzyCompare(bubble.surfaceItem.width, widthBefore, 0.1);
      fuzzyCompare(bubble.surfaceItem.height, heightBefore, 0.1);
      tryCompare(bubble, "progress", 1, 1200);
      bubble.expanded = false;
      tryCompare(bubble, "visible", false, 1200);
      compare(bubble.progress, 0);
    }
    function test_opening_from_fully_hidden_finishes_animation() {
      bubble.expanded = false; wait(30);
      verify(!bubble.visible); compare(bubble.progress, 0);
      bubble.animate = true; bubble.expanded = true;
      tryCompare(bubble, "progress", 1, 1200);
      verify(bubble.visible); compare(bubble.contentItem.opacity, 1);
    }
    function test_first_open_of_new_bubble() {
      const fresh = fixture.create("shell/BeeperBubble", window.contentItem,
        {width: 1440, height: 1080, glassEnabled: false});
      wait(30);
      compare(fresh.progress, 0); verify(!fresh.visible);
      fresh.expanded = true;
      tryCompare(fresh, "progress", 1, 1500);
      verify(fresh.visible); compare(fresh.contentItem.opacity, 1);
      fresh.destroy();
    }
    function test_osd_does_not_close_chat_or_interrupt_typing_data() {
      return [{tag: "volume", overlay: "volumeOverlayVisible"},
        {tag: "brightness", overlay: "brightnessOverlayVisible"}];
    }
    function test_osd_does_not_close_chat_or_interrupt_typing(data) {
      panel.compose();
      const composer = findChild(panel, "beeperComposer");
      composer.text = "Draft";
      const selectedChat = beeperData.currentChatID;
      const x = bubble.surfaceItem.x, y = bubble.surfaceItem.y;
      audioState[data.overlay] = true; wait(10);
      verify(composer.activeFocus); verify(panel.windowFocused);
      compare(beeperData.draftText, "Draft"); verify(bubble.expanded);
      compare(beeperData.currentChatID, selectedChat);
      compare(center.width, 280); compare(bubble.surfaceItem.width, 1280);
      compare(bubble.surfaceItem.height, 914);
      compare(bubble.surfaceItem.x, x); compare(bubble.surfaceItem.y, y);
      keyClick(Qt.Key_X); verify(beeperData.draftText.includes("x"));
      audioState[data.overlay] = false;
      verify(bubble.expanded); verify(composer.activeFocus);
      compare(beeperData.currentChatID, selectedChat);
    }
    function test_osd_does_not_change_in_flight_morph_data() {
      return [{tag: "volume", overlay: "volumeOverlayVisible"},
        {tag: "brightness", overlay: "brightnessOverlayVisible"}];
    }
    function test_osd_does_not_change_in_flight_morph(data) {
      panel.compose(); findChild(panel, "beeperComposer").text = "Keep the draft";
      const selectedChat = beeperData.currentChatID;
      // Check several exact animation frames so asynchronous frame timing cannot
      // hide a geometry jump when the source capsule switches to an OSD.
      for (const progress of [0.15, 0.45, 0.75]) {
        bubble.progress = progress;
        const width = bubble.surfaceItem.width, height = bubble.surfaceItem.height;
        const x = bubble.surfaceItem.x, y = bubble.surfaceItem.y;
        audioState[data.overlay] = true; wait(0);
        compare(bubble.progress, progress);
        compare(bubble.surfaceItem.width, width); compare(bubble.surfaceItem.height, height);
        compare(bubble.surfaceItem.x, x); compare(bubble.surfaceItem.y, y);
        compare(beeperData.currentChatID, selectedChat);
        compare(beeperData.draftText, "Keep the draft");
        verify(findChild(panel, "beeperComposer").activeFocus);
        verify(bubble.expanded);
        audioState[data.overlay] = false; wait(0);
        compare(bubble.surfaceItem.width, width); compare(bubble.surfaceItem.height, height);
      }
    }
    function test_audio_picker_owns_tab_then_returns_to_composer() {
      panel.compose(); findChild(panel, "beeperComposer").text = "Keep composing";
      audioState.audioSelectorVisible = true; wait(20);
      verify(audioPicker.activeFocus); verify(!panel.windowFocused);
      verify(!beeperData.viewFocused);
      keyClick(Qt.Key_Tab);
      compare(audioPicker.selectedKey, "mic"); compare(beeperData.networkFilter, "all");
      verify(bubble.expanded);
      keyClick(Qt.Key_Escape); wait(10);
      verify(!audioState.audioSelectorVisible); verify(bubble.expanded);
      verify(findChild(panel, "beeperComposer").activeFocus);
      compare(beeperData.draftText, "Keep composing");
    }
  }
}
