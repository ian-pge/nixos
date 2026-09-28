import QtQuick
import QtTest
import Quickshell

// Native animation fixture: synthetic chats, no messaging backend or accounts.
// BEEPER_SIDEBAR_SOURCE can point at an older packaged component for comparison.
ShellRoot {
  id: fixture
  property var sidebar: null
  property bool measuring: false
  property real lastFrame: 0
  property var frameGaps: []
  readonly property string referenceSource: Quickshell.env("BEEPER_SIDEBAR_SOURCE") || ""
  Window {
    id: window
    width: 420; height: 760; visible: true; color: "#181926"
    onFrameSwapped: {
      if (!fixture.measuring) return;
      const now = Date.now();
      if (fixture.lastFrame) fixture.frameGaps.push(now - fixture.lastFrame);
      fixture.lastFrame = now;
    }
  }
  Component.onCompleted: {
    const path = referenceSource || Quickshell.shellDir + "/../features/messenger/BeeperSidebar.qml";
    const component = Qt.createComponent("file://" + path);
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    sidebar = component.createObject(window.contentItem, {x: 20, y: 20, width: 338, height: 720,
      currentNetwork: {key: "all", name: "All", glyph: "A"}, currentChatID: "chat-0",
      chats: Array.from({length: 500}, (_, index) => ({id: "chat-" + index, title: "A group with a longer conversation title " + index,
        type: "group", network: "Telegram", participants: {total: 12}, preview: {text: "A preview that should not be laid out on every frame"}}))});
  }
  SignalSpy { id: titleWidths; signalName: "widthChanged" }
  SignalSpy { id: avatarWidths; signalName: "widthChanged" }
  TestResult { id: results }
  TestCase {
    name: "BeeperSidebar"
    when: fixture.sidebar !== null && window.visible
    function cleanupTestCase() {
      console.log("BeeperSidebar: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function test_selection_reuses_text_layout_and_avatar_geometry() {
      tryVerify(() => sidebar.list.itemAtIndex(0) !== null && sidebar.list.itemAtIndex(1) !== null);
      const first = sidebar.list.itemAtIndex(0), second = sidebar.list.itemAtIndex(1);
      wait(450);
      titleWidths.target = findChild(first, "beeperChatTitle-chat-0");
      avatarWidths.target = findChild(first, "beeperChatAvatar-chat-0");
      titleWidths.clear(); avatarWidths.clear();
      fixture.frameGaps = []; fixture.lastFrame = 0; fixture.measuring = true;
      const started = Date.now();
      console.log("Sidebar animation start");
      for (let step = 0; step < 16; ++step) {
        const index = (step + 1) % 2;
        sidebar.currentChatID = "chat-" + index;
        sidebar.revealChat(index);
        wait(80);
      }
      wait(450); fixture.measuring = false;
      const frames = fixture.frameGaps.slice().sort((a, b) => a - b);
      console.log("Sidebar animation:", JSON.stringify({titleRelayouts: titleWidths.count,
        avatarResizes: avatarWidths.count, frames: frames.length, elapsedMs: Date.now() - started,
        p95FrameMs: frames.length ? frames[Math.floor((frames.length - 1) * 0.95)] : 0,
        maxFrameMs: frames.length ? frames[frames.length - 1] : 0}));
      if (!fixture.referenceSource) {
        compare(titleWidths.count, 0, "Selection must not rewrap text on each animation frame");
        compare(avatarWidths.count, 0, "Scale the avatar as one item instead of relaying out its children");
      }
      fuzzyCompare(first.height, 128, 0.1); fuzzyCompare(second.height, 78, 0.1);
    }
  }
}
