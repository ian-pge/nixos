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
  TextMetrics { id: logoMetrics }
  TestResult { id: results }
  TestCase {
    name: "BeeperSidebar"
    when: fixture.sidebar !== null && window.visible
    function cleanupTestCase() {
      console.log("BeeperSidebar: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function test_highlight_slides_continuously_and_hidden_sidebar_settles() {
      if (fixture.referenceSource) return;
      sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(250);
      const first = sidebar.list.itemAtIndex(0), second = sidebar.list.itemAtIndex(1);
      const highlight = findChild(sidebar, "beeperChatSelection");
      compare(highlight.targetItem, first);
      fuzzyCompare(highlight.y, first.y, 0.1); fuzzyCompare(highlight.height, first.height, 0.1);
      const initialY = highlight.y;
      sidebar.currentChatID = "chat-1"; sidebar.revealChat(1);
      compare(highlight.targetItem, second); verify(highlight.running);
      fuzzyCompare(highlight.y, initialY, 0.1);
      verify(!second.selectionCoversText);
      compare(second.titleColor.toString(), "#cad3f5", "The destination text stays light until its moving background arrives");
      compare(first.titleColor.toString(), "#cad3f5", "The previous row restores its text before losing its background");
      wait(55);
      verify(highlight.y > first.y && highlight.y < second.y, "One background must travel between the rows");
      const interruptedY = highlight.y, interruptedHeight = highlight.height;
      sidebar.currentChatID = "chat-0"; sidebar.revealChat(0);
      fuzzyCompare(highlight.y, interruptedY, 0.1);
      fuzzyCompare(highlight.height, interruptedHeight, 0.1);
      wait(250);
      fuzzyCompare(highlight.y, first.y, 0.1); fuzzyCompare(highlight.height, first.height, 0.1);
      verify(first.selectionCoversText);
      sidebar.enabled = false;
      try {
        sidebar.currentChatID = "chat-1";
        compare(highlight.targetItem, second); verify(!highlight.running);
        fuzzyCompare(highlight.y, second.y, 0.1); fuzzyCompare(highlight.height, second.height, 0.1);
      } finally { sidebar.enabled = true; sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(250); }
    }
    function test_highlight_follows_keyed_reorder_without_restarting_its_animation() {
      if (fixture.referenceSource) return;
      const original = sidebar.chats;
      const highlight = findChild(sidebar, "beeperChatSelection");
      sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(250);
      const selected = highlight.targetItem;
      try {
        sidebar.chats = [original[1], original[2], original[0]].concat(original.slice(3));
        wait(30);
        compare(highlight.targetItem, selected, "Passive reorder preserves the selected delegate");
        verify(!highlight.running, "Passive layout changes must not start another slide");
        fuzzyCompare(highlight.y, selected.y, 0.1); fuzzyCompare(highlight.height, selected.height, 0.1);
        sidebar.currentChatID = "chat-3"; sidebar.revealChat(3); wait(35);
        verify(highlight.running);
        const progressBeforeReorder = highlight.progress;
        sidebar.chats = [original[0], original[3], original[1], original[2]].concat(original.slice(4));
        wait(20);
        verify(highlight.progress >= progressBeforeReorder, "Changing target geometry never rewinds the animation");
        wait(200); verify(!highlight.running);
        fuzzyCompare(highlight.y, highlight.targetItem.y, 0.1);
        fuzzyCompare(highlight.height, highlight.targetItem.height, 0.1);
      } finally { sidebar.chats = original; sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(250); }
    }
    function test_network_transitions_follow_latest_filter_without_delaying_data() {
      if (fixture.referenceSource) return;
      const original = sidebar.currentNetwork;
      const glyph = findChild(sidebar, "beeperNetworkGlyph");
      try {
        sidebar.currentNetwork = {key: "telegram", name: "Telegram", glyph: "T"};
        compare(glyph.text, "T"); compare(glyph.displayedText, "T");
        verify(glyph.running); compare(sidebar.networkProgress, 0);
        wait(40); verify(sidebar.networkProgress > 0 && sidebar.networkProgress < 1);
        sidebar.currentNetwork = {key: "whatsapp", name: "WhatsApp", glyph: "W"};
        compare(glyph.text, "W"); compare(glyph.displayedText, "W");
        wait(180); verify(!glyph.running); compare(sidebar.networkProgress, 1);
        sidebar.visible = false;
        sidebar.currentNetwork = {key: "sms", name: "SMS", glyph: "S"};
        compare(glyph.displayedText, "S"); verify(!glyph.running); compare(sidebar.networkProgress, 1);
      } finally { sidebar.visible = true; sidebar.currentNetwork = original; wait(180); }
    }
    function test_network_logos_are_not_clipped_to_the_text_advance_width() {
      if (fixture.referenceSource) return;
      const original = sidebar.currentNetwork;
      const button = findChild(sidebar, "beeperNetworkFilter");
      const glyph = findChild(sidebar, "beeperNetworkGlyph");
      logoMetrics.font = button.font;
      try {
        for (const network of [
          {key: "all", name: "All", glyph: "\uf086"},
          {key: "telegram", name: "Telegram", glyph: "\ue217"},
          {key: "whatsapp", name: "WhatsApp", glyph: "\uf232"},
          {key: "instagram", name: "Instagram", glyph: "\uf16d"},
          {key: "sms", name: "SMS", glyph: "\uf27a"}
        ]) {
          sidebar.currentNetwork = network; logoMetrics.text = network.glyph;
          wait(180);
          verify(!glyph.clip, "Nerd Font ink must not be cut at the rolling text's edge");
          compare(button.width, 54); compare(button.height, 54);
          const ink = logoMetrics.tightBoundingRect;
          const left = glyph.mapToItem(button, (glyph.width - logoMetrics.advanceWidth) / 2 + ink.x, 0).x;
          verify(left >= 0 && left + ink.width <= button.width, network.name + " fits inside its button");
          compare(glyph.progress, 1);
        }
      } finally { sidebar.currentNetwork = original; wait(180); }
    }
    function test_unread_counts_roll_but_keep_values_badge_geometry_and_manual_marks() {
      if (fixture.referenceSource) return;
      const original = sidebar.chats;
      const header = findChild(sidebar, "beeperUnreadConversationCount");
      const headerDigits = findChild(sidebar, "beeperUnreadConversationDigits");
      function setCount(value, marked) {
        sidebar.chats = original.map((chat, index) => index ? chat : Object.assign({}, chat, {unreadCount: value, isMarkedUnread: marked}));
      }
      try {
        setCount(9, false); sidebar.unreadCount = 9; wait(180);
        const badge = findChild(sidebar, "beeperUnreadBadge-chat-0");
        const digits = findChild(sidebar, "beeperUnreadDigits-chat-0");
        compare(digits.text, "9"); compare(badge.width, 26); compare(badge.height, 26);
        setCount(10, false); sidebar.unreadCount = 10;
        compare(digits, findChild(sidebar, "beeperUnreadDigits-chat-0"), "Keyed updates retain the rolling text item");
        compare(digits.text, "10"); verify(digits.running); compare(header.text, "10 unread"); verify(headerDigits.running);
        wait(40); sidebar.unreadCount = 12; setCount(12, false);
        compare(headerDigits.displayedText, "12"); compare(digits.displayedText, "12");
        wait(180); verify(!digits.running); verify(!headerDigits.running);
        sidebar.unreadCount = 11; wait(45);
        compare(headerDigits.direction, -1);
        sidebar.unreadCount = 13;
        compare(headerDigits.direction, 1); compare(headerDigits.displayedText, "13");
        wait(180); compare(headerDigits.progress, 1); verify(!headerDigits.running);
        compare(badge.width, 26); compare(badge.height, 26);
        setCount(0, true);
        verify(badge.visible); verify(!digits.visible); verify(!digits.running);
        sidebar.unreadReady = false; compare(header.text, "— unread");
        compare(headerDigits.displayedText, "—");
        sidebar.unreadLoading = true; compare(header.text, "… unread");
        compare(headerDigits.displayedText, "…");
        wait(180); verify(!headerDigits.running);
        sidebar.enabled = false; sidebar.unreadReady = true; sidebar.unreadCount = 5;
        compare(headerDigits.displayedText, "5"); verify(!headerDigits.running);
      } finally {
        sidebar.enabled = true; sidebar.unreadReady = true; sidebar.unreadLoading = false; sidebar.unreadCount = 0;
        sidebar.chats = original; wait(180);
      }
    }
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
