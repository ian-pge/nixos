import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../ui"
import "../../ui/Theme.js" as Theme
import "../../ui/Morph.js" as Morph
import "./AssistantFormat.js" as Format

// The Qwen and OpenAI conversations inside the expanded bottom notch. Data and requests
// belong to AssistantData; this view owns focus, scrolling and shortcuts.
FocusScope {
  id: root
  required property var assistantData
  property bool active: false
  property bool passive: false
  property bool windowFocused: false
  readonly property bool showingCorrection: !!assistantData.correction
  readonly property real correctionHeight: correctionReport.implicitHeight
  property bool vimEditing: true
  readonly property color accent: assistantData.current.accent
  readonly property var messages: assistantData.messages
  property int messageIndex: -1
  readonly property var selectedMessage: messageIndex >= 0 && messageIndex < messages.length ? messages[messageIndex] : null
  property Item textSelectionOwner: null
  readonly property string selectedText: textSelectionOwner?.selectedText ?? ""
  property string notice: ""
  property bool helpOpen: false
  property bool composerExpanded: false
  property real composerExpansion: composerExpanded ? 1 : 0
  Behavior on composerExpansion { enabled: root.active; NumberAnimation { duration: Morph.duration; easing.type: Easing.OutCubic } }
  // Conversation search: matching IDs come from the whole persisted history.
  property bool searchOpen: false
  property var searchMatches: []
  property int searchIndex: -1
  property int searchGeneration: 0
  property string searchError: ""
  property string revealMessageID: ""
  property string searchedQuery: ""
  property int revealPages: 0
  readonly property string activeQuery: searchOpen ? searchField.text : ""
  readonly property string currentMatchID: searchIndex >= 0 ? searchMatches[searchIndex] || "" : ""
  // Spelling correction of the draft, as in the messenger composer.
  property bool correctingSpelling: false
  property int spellingFocusRevision: 0
  property var spellingUndo: null
  property bool pinLatest: true
  property bool programmaticScroll: false
  property var scrollAnchor: null
  property real zoomWheelRemainder: 0
  readonly property real textScale: assistantData.textSize / 18
  property alias composer: composerSurface.input
  // Tests replace the system clipboard and the link opener.
  property var clipboardWriter: text => { Quickshell.clipboardText = text; }
  property var linkOpener: url => Qt.openUrlExternally(url)
  readonly property bool canUseShortcuts: active && windowFocused && !helpOpen && !showingCorrection
  readonly property bool canUseComposerShortcuts: canUseShortcuts && composer.activeFocus && !composer.inputMethodComposing
  readonly property bool canUseMessageShortcuts: canUseShortcuts && !composer.activeFocus && !searchField.activeFocus
  signal closeRequested()

  function showNotice(text) { notice = text; noticeTimer.restart(); }
  function compose() { if (!active) return; helpOpen = false; clearMessageSelection(); composer.forceActiveFocus(); }
  function focusNavigation() { if (!active) return; navigationFocus.forceActiveFocus(); }
  function clearMessageSelection() { messageIndex = -1; }
  function claimTextSelection(owner) {
    if (textSelectionOwner && textSelectionOwner !== owner) textSelectionOwner.clearTextSelection();
    textSelectionOwner = owner;
  }
  function clearTextSelection() { textSelectionOwner?.clearTextSelection(); textSelectionOwner = null; }
  function copyText(text, confirmation) { clipboardWriter(text); showNotice(confirmation); }
  function submit() {
    if (correctingSpelling || showingCorrection) { assistantData.decideCorrection(true); return; }
    if (assistantData.sendMessage()) { composerExpanded = false; clearTextSelection(); clearMessageSelection(); }
  }
  // y: the mouse selection, else the selected message's Markdown source.
  function yank() {
    if (selectedText) { copyText(selectedText, "Selection copied"); clearTextSelection(); return; }
    if (selectedMessage?.text) copyText(selectedMessage.text, "Message copied");
  }
  function openSelectedLink() {
    const links = Format.links(selectedMessage?.html);
    if (!links.length) { showNotice("This message has no link"); return; }
    showNotice(linkOpener(links[0]) === false ? "Could not open this link"
      : links.length > 1 ? "Opened the first of " + links.length + " links" : "Link opened");
  }
  function itemFor(index) { return index >= 0 ? rows.itemAt(index) : null; }
  function reveal(index, center) {
    const item = itemFor(index);
    if (!item) return;
    pinLatest = false;
    history.cancelFlick(); wheel.reset();
    const top = item.y, bottom = item.y + item.height;
    let target = history.contentY;
    if (center) target = top + (item.height - history.height) / 2;
    else if (top < history.contentY) target = top;
    else if (bottom > history.contentY + history.height) target = bottom - history.height;
    scrollTo(Math.max(0, Math.min(Math.max(0, history.contentHeight - history.height), target)));
  }
  function moveMessageSelection(delta) {
    if (!messages.length) return;
    clearTextSelection();
    messageIndex = messageIndex < 0 ? messages.length - 1 : Math.max(0, Math.min(messages.length - 1, messageIndex + delta));
    focusNavigation();
    reveal(messageIndex, false);
    if (messageIndex === 0) assistantData.loadOlderMessages();
  }
  function scrollTo(y) { programmaticScroll = true; history.contentY = y; programmaticScroll = false; }
  // Following takes over from a wheel glide still heading for the old end.
  function scrollToEnd() { wheel.reset(); column.forceLayout(); scrollTo(Math.max(0, history.contentHeight - history.height)); }
  function followLatest() { if (active && pinLatest) scrollToEnd(); }
  function changeTextSize(steps) {
    const size = steps === 0 ? 18 : assistantData.textSize + steps * 2;
    const atEnd = pinLatest;
    assistantData.setTextSize(size);
    if (atEnd) Qt.callLater(scrollToEnd);
  }
  function zoomWheel(angleDelta, pixelDelta) {
    zoomWheelRemainder += angleDelta ? angleDelta / 120 : pixelDelta / 60;
    const steps = Math.trunc(zoomWheelRemainder);
    if (steps) { zoomWheelRemainder -= steps; changeTextSize(steps); }
  }
  function openSearch() {
    helpOpen = false; searchOpen = true; searchError = "";
    Qt.callLater(() => { if (searchOpen) { searchField.forceActiveFocus(); searchField.selectAll(); } });
  }
  function closeSearch() {
    ++searchGeneration; searchOpen = false; searchField.text = ""; searchMatches = []; searchIndex = -1;
    searchError = ""; revealMessageID = ""; searchedQuery = ""; focusNavigation();
  }
  function runSearch() {
    const query = searchField.text, generation = ++searchGeneration;
    revealMessageID = ""; searchedQuery = query;
    if (!query.trim()) { searchMatches = []; searchIndex = -1; searchError = ""; return; }
    assistantData.search(query, (result, error) => {
      if (generation !== searchGeneration) return;
      searchMatches = error ? [] : result?.ids || [];
      searchError = error ? error.message || "Search failed" : searchMatches.length ? "" : "No match";
      searchIndex = searchMatches.length - 1;
      revealMatch();
    });
  }
  function moveMatch(delta) {
    if (!searchMatches.length) return;
    searchIndex = (searchIndex + delta + searchMatches.length) % searchMatches.length;
    revealMatch();
  }
  // Load older pages until the match is present; stop at the history's start.
  function revealMatch() {
    const id = currentMatchID;
    if (!id) return;
    const index = messages.findIndex(message => message.id === id);
    if (index >= 0) { revealMessageID = ""; messageIndex = index; Qt.callLater(() => reveal(index, true)); return; }
    revealMessageID = id;
    if (assistantData.hasOlderMessages) assistantData.loadOlderMessages();
    else { revealMessageID = ""; searchError = "This message is no longer in the conversation"; }
  }
  function correctSpelling(undo = false, provider = "qwen") {
    if (!canUseComposerShortcuts) return;
    if (correctingSpelling) { return; }
    if (undo) {
      if (!spellingUndo || assistantData.draftText !== spellingUndo.after) { return; }
      assistantData.draftText = spellingUndo.before;
      composer.cursorPosition = Math.min(spellingUndo.cursor, composer.length);
      assistantData.finishCorrection?.(spellingUndo.report, "undone"); spellingUndo = null; return;
    }
    const original = composer.text, selected = composer.selectionStart !== composer.selectionEnd;
    const start = selected ? composer.selectionStart : 0, end = selected ? composer.selectionEnd : original.length;
    const text = original.slice(start, end);
    if (!text.trim()) { return; }
    const cursor = composer.cursorPosition;
    const selectionStart = composer.selectionStart, selectionEnd = composer.selectionEnd;
    correctingSpelling = true;
    assistantData.correctText(text, (result, error) => {
      try {
        if (error || result?.cancelled) { return; }
        // Apply only to the exact draft, caret and focus that were corrected.
        if (composer.text !== original
            || composer.cursorPosition !== cursor || composer.selectionStart !== selectionStart || composer.selectionEnd !== selectionEnd) {
          assistantData.finishCorrection?.(result, "cancelled"); return;
        }
        if (!result?.edits?.length) { assistantData.finishCorrection?.(result, "unchanged"); return; }
        const corrected = original.slice(0, start) + result.text + original.slice(end);
        spellingUndo = {before: original, after: corrected, cursor: cursor, report: result};
        assistantData.draftText = corrected;
        composer.cursorPosition = Math.max(0, Math.min(corrected.length, cursor + result.text.length - text.length));
        assistantData.finishCorrection?.(result, "applied");
      } finally { correctingSpelling = false; }
    }, provider);
  }
  // Each model keeps its own conversation and draft; switching never sends
  // one conversation to the other model.
  function switchModel(delta) {
    if (!active) return;
    const inComposer = composer.activeFocus;
    clearTextSelection(); clearMessageSelection();
    if (searchOpen) closeSearch();
    composerExpanded = false; helpOpen = false;
    assistantData.cycleConversation(delta);
    pinLatest = true;
    // From Vim's normal mode the caret stays in the composer.
    if (!inComposer) focusNavigation();
  }
  // Ctrl+Tab: Qwen thinks or not; OpenAI steps from low to extra high.
  function cycleThinking(delta) {
    if (!active) return;
    root.assistantData.cycleThinking(delta);
    showNotice("Thinking · " + root.assistantData.thinkingName);
  }
  function handleEscape() {
    if (showingCorrection) { assistantData.decideCorrection(false); return; }
    if (helpOpen) helpOpen = false;
    else if (selectedText) clearTextSelection();
    else if (searchOpen) closeSearch();
    else if (composerExpanded && composer.activeFocus) composerExpanded = false;
    else if (composer.activeFocus || messageIndex >= 0) { clearMessageSelection(); focusNavigation(); }
    else closeRequested();
  }

  onActiveChanged: {
    if (active) {
      pinLatest = true; Qt.callLater(scrollToEnd);
      if (!passive) Qt.callLater(showingCorrection ? focusNavigation : compose);
    }
    else {
      composerExpanded = false; helpOpen = false; clearTextSelection(); clearMessageSelection();
      if (searchOpen) closeSearch();
      assistantData.flushDraft();
    }
  }
  onWindowFocusedChanged: ++spellingFocusRevision
  Connections {
    target: root.composer
    function onActiveFocusChanged() { ++root.spellingFocusRevision; if (root.composer.activeFocus) root.clearMessageSelection(); }
  }
  Connections {
    target: root.assistantData
    function onMessagesUpdating() {
      // Keep the reading position when older pages are prepended.
      if (root.pinLatest) { root.scrollAnchor = null; return; }
      const item = column.childAt(10, history.contentY + 2);
      root.scrollAnchor = item && item.message ? {id: item.message.id, offset: history.contentY - item.y} : null;
    }
    function onMessagesLoaded(older) {
      Qt.callLater(() => {
        column.forceLayout();
        if (root.pinLatest) root.scrollToEnd();
        else if (root.scrollAnchor) {
          const index = root.messages.findIndex(message => message.id === root.scrollAnchor.id);
          const item = root.itemFor(index);
          if (item) root.scrollTo(item.y + root.scrollAnchor.offset);
        }
        root.scrollAnchor = null;
        if (root.revealMessageID) root.revealMatch();
      });
    }
    function onMessageSent() { root.pinLatest = true; Qt.callLater(root.scrollToEnd); }
    function onConversationReset() {
      root.clearTextSelection(); root.clearMessageSelection();
      if (root.searchOpen) root.closeSearch();
      root.pinLatest = true;
      if (root.active) root.showNotice("Conversation reset");
    }
    function onConversationSwitched() { root.spellingUndo = null; root.pinLatest = true; Qt.callLater(root.scrollToEnd); }
    function onModelUnloaded() { if (root.active) root.showNotice("Model unloaded · Next message will reload it"); }
  }

  Item { id: navigationFocus; focus: true }
  onShowingCorrectionChanged: if (showingCorrection && activeFocus) navigationFocus.forceActiveFocus()
  Shortcut {
    sequences: ["Return", "Enter"]; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.active && root.windowFocused && root.showingCorrection
    onActivated: root.assistantData.decideCorrection(true)
  }
  Shortcut {
    sequence: "Escape"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.active && root.windowFocused && root.showingCorrection
    onActivated: root.assistantData.decideCorrection(false)
  }
  Keys.onPressed: event => {
    if (!root.active || !root.windowFocused) return;
    if (event.key === Qt.Key_Escape) { root.handleEscape(); event.accepted = true; return; }
    if (root.helpOpen) { event.accepted = true; return; }
    if (composer.activeFocus || searchField.activeFocus) return;
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && root.selectedText) {
      root.copyText(root.selectedText, "Selection copied"); event.accepted = true; return;
    }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
    const key = event.text;
    if (root.searchOpen && (key === "n" || key === "N")) { root.moveMatch(key === "N" ? -1 : 1); event.accepted = true; }
    else if (key === "j" || key === "k") { root.moveMessageSelection(key === "j" ? 1 : -1); event.accepted = true; }
    else if (key === "G") { root.pinLatest = true; root.clearMessageSelection(); root.scrollToEnd(); event.accepted = true; }
    else if (key === "y") { if (!event.isAutoRepeat) root.yank(); event.accepted = true; }
    else if (key === "l" && root.selectedMessage) { if (!event.isAutoRepeat) root.openSelectedLink(); event.accepted = true; }
    else if (key === "/") { root.openSearch(); event.accepted = true; }
    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) { if (!event.isAutoRepeat) root.switchModel(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1); event.accepted = true; }
    else if (key === "?") { if (!event.isAutoRepeat) root.helpOpen = true; event.accepted = true; }
    else if (key === "i" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.compose(); event.accepted = true; }
  }
  Shortcut {
    sequence: "Ctrl+S"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseShortcuts && composerSurface.canReset
    onActivated: root.assistantData.resetConversation()
  }
  Shortcut {
    sequence: "Ctrl+D"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseShortcuts && composerSurface.canUnload
    onActivated: root.assistantData.unloadModel()
  }
  Shortcut {
    sequence: "Ctrl+Tab"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseShortcuts && !composer.inputMethodComposing
    onActivated: root.cycleThinking(1)
  }
  Shortcut {
    sequences: ["Ctrl+Shift+Tab", "Ctrl+Shift+Backtab"]; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseShortcuts && !composer.inputMethodComposing
    onActivated: root.cycleThinking(-1)
  }
  Shortcut {
    sequence: "Ctrl+Space"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseComposerShortcuts
    onActivated: root.composerExpanded = !root.composerExpanded
  }
  Shortcut {
    sequence: "Alt+Tab"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseComposerShortcuts
    onActivated: root.correctSpelling(false, "openai")
  }
  Shortcut {
    sequence: "Ctrl+Alt+Tab"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseComposerShortcuts
    onActivated: root.correctSpelling(false)
  }
  Shortcut {
    sequence: "Ctrl+Alt+Shift+Tab"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseComposerShortcuts
    onActivated: root.correctSpelling(true)
  }
  Shortcut {
    sequence: "Ctrl+H"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseShortcuts
    onActivated: root.focusNavigation()
  }
  Shortcut {
    sequence: "Ctrl+L"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseShortcuts
    onActivated: root.compose()
  }
  Shortcut {
    sequence: "Ctrl+J"; context: Qt.ApplicationShortcut
    enabled: root.canUseShortcuts && !composer.inputMethodComposing
    onActivated: root.searchOpen ? root.moveMatch(1) : root.moveMessageSelection(1)
  }
  Shortcut {
    sequence: "Ctrl+K"; context: Qt.ApplicationShortcut
    enabled: root.canUseShortcuts && !composer.inputMethodComposing
    onActivated: root.searchOpen ? root.moveMatch(-1) : root.moveMessageSelection(-1)
  }
  Shortcut {
    sequence: "Ctrl+/"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseShortcuts && !composer.inputMethodComposing
    onActivated: root.openSearch()
  }
  Shortcut {
    sequences: ["Ctrl++", "Ctrl+=", "Ctrl+Shift++", "Ctrl+Shift+="]; context: Qt.ApplicationShortcut
    enabled: root.canUseShortcuts
    onActivated: root.changeTextSize(1)
  }
  Shortcut { sequence: "Ctrl+-"; context: Qt.ApplicationShortcut; enabled: root.canUseShortcuts; onActivated: root.changeTextSize(-1) }
  Shortcut { sequence: "Ctrl+0"; context: Qt.ApplicationShortcut; enabled: root.canUseShortcuts; onActivated: root.changeTextSize(0) }

  ColumnLayout {
    id: layout
    visible: !root.showingCorrection
    anchors { fill: parent; leftMargin: 22; rightMargin: 22; topMargin: 16; bottomMargin: 18 }
    spacing: 10
    Rectangle {
      id: searchBar
      objectName: "assistantSearchBar"
      Layout.fillWidth: true
      Layout.preferredHeight: root.searchOpen ? 40 : 0
      visible: root.searchOpen
      radius: 20; color: Theme.surface
      RowLayout {
        anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
        spacing: 8
        Icon { name: "search"; size: 16; color: root.accent }
        TextField {
          id: searchField
          objectName: "assistantSearchField"
          Layout.fillWidth: true
          placeholderText: "Search the conversation"
          color: Theme.foreground; placeholderTextColor: Theme.inactive
          font { family: "Ubuntu Nerd Font"; pixelSize: 15 }
          background: null
          onTextChanged: searchTimer.restart()
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              searchTimer.stop();
              // Enter on an unchanged query steps to the previous (older) match.
              if (searchField.text === root.searchedQuery && root.searchMatches.length) root.moveMatch(event.modifiers & Qt.ShiftModifier ? 1 : -1);
              else root.runSearch();
              event.accepted = true;
            }
          }
        }
        Text {
          objectName: "assistantSearchCount"
          text: root.searchError || (root.searchMatches.length ? (root.searchIndex + 1) + " / " + root.searchMatches.length : "")
          color: root.searchError ? Theme.error : Theme.secondary
          font { family: "Ubuntu Nerd Font"; pixelSize: 13 }
        }
      }
      Timer { id: searchTimer; interval: 220; onTriggered: root.runSearch() }
    }
    Item {
      Layout.fillWidth: true; Layout.fillHeight: true
      Flickable {
        id: history
        objectName: "assistantHistory"
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: column.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        // Only a user gesture (wheel, drag, scrollbar) releases the bottom anchor,
        // and returning to the end restores it. Layout can move contentY too, e.g.
        // pixel rounding while a reply grows: that must not stop the follow.
        readonly property bool userScrolling: moving || wheel.driving || historyScrollBar.pressed || wheelGesture.running
        readonly property bool atEnd: contentY >= contentHeight - height - 8
        property real lastContentY: 0
        onContentYChanged: {
          const upward = contentY < lastContentY - 0.5;
          lastContentY = contentY;
          if (root.programmaticScroll) return;
          // A gesture still settling at the bottom while the reply grows is
          // not a request to stop following: only moving up releases it.
          if (userScrolling && atEnd) root.pinLatest = true;
          else if (userScrolling && upward) root.pinLatest = false;
          if (contentY < 240) Qt.callLater(root.assistantData.loadOlderMessages);
        }
        onMovementEnded: if (atEnd) root.pinLatest = true
        onContentHeightChanged: Qt.callLater(root.followLatest)
        onHeightChanged: Qt.callLater(root.followLatest)
        ScrollBar.vertical: ScrollBar { id: historyScrollBar; policy: ScrollBar.AsNeeded }
        AcceleratedScroll { id: wheel; flickable: history; inputEnabled: root.active; onScrolled: wheelGesture.restart() }
        // Touchpad gestures arrive as native scroll events between movements.
        Timer { id: wheelGesture; interval: 200 }
        Column {
          id: column
          width: history.width
          spacing: 10
          topPadding: 4
          Text {
            width: parent.width
            visible: !root.assistantData.hasOlderMessages && root.messages.length > 0
            horizontalAlignment: Text.AlignHCenter
            text: root.messages.length ? Format.dateLabel(root.messages[0].timestamp) : ""
            color: Theme.inactive
            font { family: "Ubuntu Nerd Font"; pixelSize: 13 }
          }
          Repeater {
            id: rows
            model: KeyedListModel { rows: root.messages; immutableRows: true }
            delegate: AssistantMessage {
              id: bubble
              required property var row
              required property int index
              width: column.width
              message: row
              mathRenderer: root.assistantData.mathRenderer
              baseSize: 18
              textScale: root.textScale
              accent: root.accent
              assistantName: root.assistantData.title
              logo: root.assistantData.current.logo
              selected: index === root.messageIndex
              searchQuery: root.activeQuery
              currentMatch: !!root.currentMatchID && row.id === root.currentMatchID
              onSelectedRequested: { root.messageIndex = index; root.focusNavigation(); }
              onTextSelectionStarted: root.claimTextSelection(bubble)
              onOpenRequested: url => root.linkOpener(url)
              // Only new messages arriving at the end animate, never a page.
              Component.onCompleted: if (root.active && root.pinLatest && root.assistantData.sending && index >= root.messages.length - 2) playArrival()
            }
          }
        }
      }
      // An empty conversation shows only the model: logo, name and access.
      // Tab or a click switches model; the logo changes without animation.
      Row {
        id: modelCard
        objectName: "assistantModelCard"
        anchors.centerIn: parent
        spacing: 20
        visible: root.messages.length === 0
        AssistantModelSwitch {
          anchors.verticalCenter: parent.verticalCenter
          size: 76
          model: root.assistantData.current
          onClicked: root.switchModel(1)
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            text: root.assistantData.title
            textFormat: Text.PlainText
            color: Theme.foreground
            font { family: "Ubuntu Nerd Font"; pixelSize: 34; weight: Font.DemiBold }
          }
          Text {
            objectName: "assistantStatus"
            text: !root.assistantData.available ? "Assistant service starting…"
              : root.assistantData.unloading || root.assistantData.unloadPending ? "Unloading from GPU…"
              : root.assistantData.resetting ? "Resetting…" : root.assistantData.modelLabel
            textFormat: Text.PlainText
            color: Theme.secondary
            font { family: "Ubuntu Nerd Font"; pixelSize: 21 }
          }
        }
      }
      Rectangle {
        objectName: "assistantNotice"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 12 }
        width: noticeText.implicitWidth + 36; height: 34; radius: 17
        color: Theme.surfaceRaised
        visible: root.notice !== ""
        Text { id: noticeText; objectName: "assistantNoticeText"; anchors.centerIn: parent; text: root.notice; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: 15 } }
      }
      Timer { id: noticeTimer; interval: 1600; onTriggered: root.notice = "" }
    }
    Rectangle {
      id: errorBanner
      objectName: "assistantError"
      Layout.fillWidth: true
      implicitHeight: errorText.implicitHeight + 16
      visible: !!root.assistantData.lastError
      color: Qt.alpha(Theme.error, 0.12); radius: 10
      Text {
        id: errorText
        anchors { left: parent.left; right: dismissError.left; verticalCenter: parent.verticalCenter; margins: 10 }
        text: root.assistantData.lastError; textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: Theme.error; font { family: "Ubuntu Nerd Font"; pixelSize: 14 }
      }
      Button {
        id: dismissError
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        width: 28; height: 28; focusPolicy: Qt.NoFocus
        Accessible.name: "Dismiss error"
        background: null
        contentItem: Icon { name: "x"; size: 14; color: Theme.error }
        onClicked: root.assistantData.lastError = ""
      }
    }
    // The composer, then the thinking level as a dot on the far right.
    RowLayout {
      id: composerRow
      // The history keeps its gap above the composer even at zero height:
      // counting it keeps the composer's bottom edge still while it grows.
      readonly property real expandedHeight: Math.max(composerSurface.implicitHeight, layout.height - layout.spacing
        - (searchBar.visible ? searchBar.height + layout.spacing : 0) - (errorBanner.visible ? errorBanner.height + layout.spacing : 0))
      Layout.fillWidth: true
      readonly property real targetHeight: Math.round(composerSurface.implicitHeight + (expandedHeight - composerSurface.implicitHeight) * root.composerExpansion)
      // Exactly this height: the composer's fillHeight must not stretch the row.
      Layout.preferredHeight: targetHeight
      Layout.maximumHeight: targetHeight
      spacing: 14
      AssistantComposer {
        id: composerSurface
        Layout.fillWidth: true
        Layout.fillHeight: true
        expanded: root.composerExpanded || root.composerExpansion > 0
        assistantData: root.assistantData
        active: root.active
        vimEditing: root.vimEditing
        textSize: root.assistantData.textSize
        accent: root.accent
        onSubmitRequested: root.submit()
        onCopyRequested: text => root.copyText(text, "Text copied")
        onSwitchRequested: delta => root.switchModel(delta)
      }
      AssistantThinkingDot {
        // Centered on the composer's buttons, which stay at its bottom.
        Layout.alignment: Qt.AlignBottom
        Layout.bottomMargin: composerSurface.buttonCenter - height / 2
        color: root.assistantData.thinkingColor
        level: root.assistantData.thinkingName
        onClicked: root.cycleThinking(1)
      }
    }
  }
  AssistantCorrection {
    id: correctionReport
    anchors.fill: parent
    visible: root.showingCorrection
    report: root.assistantData.correction
    onFocusRequested: root.focusNavigation()
  }
  // Ctrl+wheel zooms the text; plain wheel stays with the history.
  WheelHandler {
    target: null
    enabled: root.active && !root.helpOpen
    acceptedModifiers: Qt.ControlModifier
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => { root.zoomWheel(event.angleDelta.y, event.pixelDelta.y); event.accepted = true; }
  }
  Rectangle {
    objectName: "assistantHelp"
    anchors.fill: parent
    visible: root.helpOpen
    color: Qt.alpha("#000000", 0.92)
    radius: 18
    MouseArea { anchors.fill: parent; onClicked: root.helpOpen = false }
    Column {
      anchors.centerIn: parent
      spacing: 6
      Repeater {
        model: [
          "CONVERSATION",
          "Enter     Send · Shift + Enter     New line",
          "Ctrl + s     Reset conversation and context (draft kept)",
          "Tab / Shift + Tab     Switch between Qwen and OpenAI (outside the draft)",
          "Ctrl + Tab / + Shift     Thinking: Qwen on / off · OpenAI low → extra high",
          "Ctrl + d     Unload Qwen from the GPU",
          "Send button during a reply     Stop the reply",
          "Ctrl + Space     Expand / restore the writing area",
          "Alt + Tab     Correct with GPT · Ctrl + Alt + Tab     Qwen · + Shift: undo",
          "Ctrl + h / Ctrl + l     Messages / composer",
          "MESSAGES",
          "Ctrl + j / k  or  j / k     Select the next / previous message",
          "y     Copy the selection, else the message's Markdown",
          "l     Open the message's first link · G     Latest message",
          "Ctrl + /  or  /     Search · n / N or Ctrl + j / k     Next / previous match",
          "Ctrl + + / − / 0, Ctrl + wheel     Text size",
          "Esc     Step back, then fold into the clock · Cmd + I     Toggle"
        ]
        delegate: Text {
          required property string modelData
          text: modelData
          textFormat: Text.PlainText
          color: modelData === modelData.toUpperCase() ? root.accent : Theme.foreground
          font { family: "JetBrainsMono Nerd Font"; pixelSize: modelData === modelData.toUpperCase() ? 13 : 15; weight: modelData === modelData.toUpperCase() ? Font.Bold : Font.Normal }
          topPadding: modelData === modelData.toUpperCase() ? 10 : 0
        }
      }
    }
  }
}
