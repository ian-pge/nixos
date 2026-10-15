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
  property bool watchRowSpacing: false
  property real smallestRowGap: 1000
  property int spacingFrames: 0
  readonly property string referenceSource: Quickshell.env("BEEPER_SIDEBAR_SOURCE") || ""
  Window {
    id: window
    width: 420; height: 760; visible: true; color: "#181926"
    onFrameSwapped: {
      if (fixture.watchRowSpacing) {
        ++fixture.spacingFrames;
        for (let index = 0; index < 3; ++index) {
          const row = sidebar.list.itemAtIndex(index), next = sidebar.list.itemAtIndex(index + 1);
          if (row && next) {
            const bodyHeight = item => Math.max(item.textHeight, 48 + (item.avatarDiameter - 48) * item.selectionProgress);
            const bottom = row.visualY + (row.visualHeight + bodyHeight(row)) / 2;
            const top = next.visualY + (next.visualHeight - bodyHeight(next)) / 2;
            fixture.smallestRowGap = Math.min(fixture.smallestRowGap, top - bottom);
          }
        }
      }
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
  SignalSpy { id: modelMoves; target: fixture.sidebar?.list.model ?? null; signalName: "rowsMoved" }
  SignalSpy { id: modelRemovals; target: fixture.sidebar?.list.model ?? null; signalName: "rowsRemoved" }
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
        fuzzyCompare(highlight.y, selected.visualY, 0.1); fuzzyCompare(highlight.height, selected.height, 0.1);
        wait(250); // Finish reflow before exercising an independent keyboard slide.
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
    function test_catalogue_reflow_data() {
      return [{tag: "archive-500", count: 500, remove: true}, {tag: "read-500", count: 500, remove: false},
        {tag: "archive-2000", count: 2000, remove: true}, {tag: "read-2000", count: 2000, remove: false}];
    }
    function test_bulk_reorder_reuses_visible_slots_and_preserves_the_viewport_anchor() {
      if (fixture.referenceSource) return;
      const original = sidebar.chats;
      try {
        sidebar.list.positionViewAtIndex(100, ListView.Beginning); wait(250);
        const top = sidebar.list.indexAt(1, sidebar.list.contentY + 2);
        const anchor = sidebar.list.itemAtIndex(top);
        const id = anchor.row.id, offset = sidebar.list.contentY - anchor.y;
        modelMoves.clear();
        sidebar.chats = original.slice().reverse(); wait(250);
        compare(modelMoves.count, 0);
        const index = sidebar.chats.findIndex(chat => chat.id === id);
        const restored = sidebar.list.itemAtIndex(index); verify(restored !== null);
        fuzzyCompare(sidebar.list.contentY - restored.y, offset, 0.5);
      } finally { sidebar.chats = original; sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(300); }
    }
    function test_restored_chat_selection_ignores_its_old_fading_row() {
      if (fixture.referenceSource) return;
      const original = sidebar.chats;
      try {
        sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(300);
        const outgoing = sidebar.list.itemAtIndex(1);
        sidebar.chats = [original[0]].concat(original.slice(2)); sidebar.list.forceLayout();
        verify(outgoing.retiring); verify(!outgoing.enabled);
        sidebar.chats = original; sidebar.currentChatID = "chat-1"; sidebar.revealChat(1);
        const restored = sidebar.list.itemAtIndex(1);
        verify(restored !== outgoing); verify(!outgoing.chosen); verify(restored.chosen);
        compare(findChild(sidebar, "beeperChatSelection").targetItem, restored);
        compare(findChild(sidebar, "beeperChatRow-chat-1"), restored);
      } finally { sidebar.chats = original; sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(300); }
    }
    function test_catalogue_reflow(data) {
      const original = sidebar.chats;
      const rows = Array.from({length: data.count}, (_, i) => ({id: "chat-" + i,
        title: "Synthetic conversation " + i, network: "Telegram", preview: {text: "Synthetic preview"}, unreadCount: 1}));
      try {
        sidebar.chats = rows; sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(300);
        const next = sidebar.list.itemAtIndex(1), following = sidebar.list.itemAtIndex(2);
        const initialY = next.y, highlight = findChild(sidebar, "beeperChatSelection");
        modelMoves.clear(); modelRemovals.clear();
        fixture.frameGaps = []; fixture.lastFrame = Date.now(); fixture.measuring = true;
        const started = Date.now();
        sidebar.chats = data.remove ? rows.slice(1)
          : rows.slice(1).concat([Object.assign({}, rows[0], {unreadCount: 0})]);
        sidebar.currentChatID = "chat-1"; sidebar.revealChat(0);
        const applyMs = Date.now() - started;
        if (!fixture.referenceSource) {
          compare(modelMoves.count, data.remove ? 0 : 1);
          compare(modelRemovals.count, data.remove ? 1 : 0);
          compare(sidebar.list.itemAtIndex(0), next, "Keep the surviving delegate and its avatar");
          wait(35);
          verify(next.visualY < initialY && next.visualY > sidebar.list.originY, "The next row glides into place");
          for (let frame = 0; frame < 10; ++frame) {
            verify(following.visualY - next.visualY - next.visualHeight >= -1, "Growing contents must not overlap the following row");
            fuzzyCompare(highlight.y, next.visualY, 0.1);
            fuzzyCompare(highlight.height, next.visualHeight, 0.1);
            wait(20);
          }
          fuzzyCompare(following.y - next.y, next.height + sidebar.list.spacing, 0.5);
        } else wait(250);
        fixture.measuring = false;
        const frames = fixture.frameGaps.slice().sort((a, b) => a - b);
        console.log("Sidebar reflow:", JSON.stringify({action: data.remove ? "archive" : "read", chats: data.count,
          modelMoves: modelMoves.count, modelRemovals: modelRemovals.count, applyMs: applyMs,
          p95FrameMs: frames.length ? frames[Math.floor((frames.length - 1) * 0.95)] : 0,
          maxFrameMs: frames.length ? frames[frames.length - 1] : 0}));
      } finally {
        fixture.measuring = false; sidebar.chats = original; sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(300);
      }
    }
    function test_repeated_removals_and_navigation_during_reflow_settle_without_overlap_data() {
      return [{tag: "rapid", pause: 10}, {tag: "mid-reflow", pause: 45}, {tag: "near-end", pause: 150}];
    }
    function test_repeated_removals_and_navigation_during_reflow_settle_without_overlap(data) {
      if (fixture.referenceSource) return;
      const original = sidebar.chats;
      try {
        sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(250);
        for (let i = 1; i <= 4; ++i) {
          sidebar.chats = original.slice(i);
          sidebar.currentChatID = "chat-" + i; sidebar.revealChat(0);
          wait(data.pause);
        }
        fixture.smallestRowGap = 1000; fixture.spacingFrames = 0; fixture.watchRowSpacing = true;
        sidebar.currentChatID = "chat-5"; sidebar.revealChat(1);
        wait(500); fixture.watchRowSpacing = false;
        verify(fixture.spacingFrames > 0);
        verify(fixture.smallestRowGap >= 0, "Conversation text and avatars must not overlap during navigation: gap " + fixture.smallestRowGap);
        for (let index = 0; index < 4; ++index) {
          tryVerify(() => {
            const row = sidebar.list.itemAtIndex(index), next = sidebar.list.itemAtIndex(index + 1);
            return row !== null && next !== null && Math.abs(next.y - row.y - row.height - sidebar.list.spacing) <= 0.5;
          }, 1000);
        }
        compare(findChild(sidebar, "beeperChatSelection").targetItem.row.id, "chat-5");
      } finally {
        fixture.watchRowSpacing = false;
        if (results.failed) console.log("Reflow failed geometry", JSON.stringify({scroll: sidebar.list.contentY, origin: sidebar.list.originY,
          smallestContentGap: fixture.smallestRowGap, frames: fixture.spacingFrames,
          rows: Array.from({length: 5}, (_, i) => { const row = sidebar.list.itemAtIndex(i); return row ? {id: row.row.id, y: row.y, h: row.height, visual: row.visualHeight} : null; })}));
        sidebar.chats = original; sidebar.currentChatID = "chat-0"; sidebar.revealChat(0); wait(300);
      }
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
