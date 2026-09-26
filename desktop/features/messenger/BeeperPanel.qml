import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

FocusScope {
  id: root
  required property var beeperData
  property bool active: false
  property bool windowFocused: false
  property bool dictating: false
  property real dictationEnergy: 0
  property string navigation: "chats"
  property int chatIndex: 0
  property int messageIndex: -1
  readonly property string networkFilter: beeperData.networkFilter
  readonly property bool showArchived: beeperData.showArchived
  readonly property bool unreadFirst: beeperData.unreadFirst
  readonly property var currentNetwork: Format.networkBadge(networkFilter)
  // The filter logo describes the view; conversation controls describe its
  // actual platform, including when the view contains every network.
  readonly property string conversationConnectionIssue: Format.chatConnectionIssue(beeperData.currentChat, beeperData.accountConnectionIssues, beeperData.serviceConnectionIssue)
  readonly property color conversationAccent: conversationConnectionIssue ? Theme.error : Theme.beeperNetworkColors[Format.networkBadge(beeperData.currentChat?.network).key] || Theme.secondary
  property bool searchOpen: false
  property bool locatingSearchResult: false
  property string locatingSearchChatID: ""
  property string modal: ""
  property string editMessageID: ""
  property string editText: ""
  property var previewAttachment: null
  property bool externalPhotoPreview: false
  readonly property bool photoPreviewOpen: modal === "media"
    && ["image", "gif", "video"].includes(Format.attachmentType(previewAttachment || {}))
  readonly property bool videoPreviewOpen: modal === "media" && Format.attachmentType(previewAttachment || {}) === "video"
  property var recordingAttachment: null
  property string recordingChatID: ""
  property bool preparingRecording: false
  property var recorder: null
  property bool gPending: false
  property string pendingOpenMessageID: ""
  property string displayedChatID: ""
  property int targetPageCount: 0
  property bool restoringView: false
  property bool pinLatest: false
  readonly property bool historyInteracting: messageWheel.driving || messageList.moving || historyWheelTimer.running || historyScrollBar.pressed
  property string selectedMessageIDBeforeUpdate: ""
  property real zoomWheelRemainder: 0
  // Child views expose only the focus and list controls owned by this coordinator.
  property alias searchField: sidebar.searchInput
  property alias chatList: sidebar.list
  property alias composer: composerSurface.input
  readonly property bool emojiPickerOpen: composerSurface?.emojiPickerOpen || false
  property alias tokenField: connectionSurface.tokenInput
  property alias modalSurface: dialogs.surface
  readonly property bool compact: width < 780
  readonly property bool recording: recorder !== null && recorder.recording
  readonly property var selectedMessage: messageIndex >= 0 && messageIndex < beeperData.messages.length ? beeperData.messages[messageIndex] : null
  readonly property var filteredChats: Format.orderChats(beeperData.chats.filter(chat => Format.isChatInView(chat, showArchived)
    && (networkFilter === "all" || Format.networkBadge(chat.network).key === networkFilter)
    && (!searchField.text || (Format.chatTitle(chat) + " " + Format.preview(chat)).toLowerCase().includes(searchField.text.toLowerCase()))), unreadFirst)
  readonly property bool canCycleNetwork: active && windowFocused && !modal && !beeperData.tokenRequired
    && !composerSurface?.emojiPickerOpen
    && !(connectionSurface?.visible ?? true)
    && !composer?.activeFocus && !searchField?.activeFocus && !tokenField?.activeFocus
    && !recording && !preparingRecording && !messageSearch.opened
  readonly property bool canZoomText: active && windowFocused && !modal
    && !composerSurface?.emojiPickerOpen
    && !connectionSurface.visible
  readonly property bool canNavigateMessages: active && windowFocused && !modal
    && !composerSurface?.emojiPickerOpen
    && !connectionSurface.visible && !searchField.activeFocus && !tokenField.activeFocus
    && !conversationSearchBar.input.activeFocus
    && !composer.inputMethodComposing && !!beeperData.currentChatID
  readonly property var quickReactions: Format.quickReactions(beeperData.currentChat)
  signal closeRequested()
  signal nativeDialogOpened()
  signal nativeDialogClosed()
  implicitWidth: 1280
  implicitHeight: 900
  clip: true

  function clearMessageSelection() { messageIndex = -1; selectedMessageIDBeforeUpdate = ""; }
  function focusNavigation() { if (!active) return; clearMessageSelection(); navigation = "chats"; if (connectionSurface.visible) connectionSurface.focusInput(true); else navigationFocus.forceActiveFocus(); }
  function syncChatIndex() {
    const selected = filteredChats.findIndex(chat => chat.id === beeperData.currentChatID);
    chatIndex = selected >= 0 ? selected : Math.max(0, Math.min(chatIndex, filteredChats.length - 1));
  }
  function ensureInitialChat() {
    if (!active || !beeperData.connected || beeperData.currentChatID || !filteredChats.length) return;
    chooseChat(0);
  }
  function openChatSearch() { closeConversationSearch(false); searchOpen = true; Qt.callLater(() => searchField.forceActiveFocus()); }
  function closeChatSearch() { searchOpen = false; searchField.text = ""; if (active) navigationFocus.forceActiveFocus(); }
  function openConversationSearch(query = "") {
    closeChatSearch(); messageSearch.opened = true;
    if (query) messageSearch.query = query;
    Qt.callLater(() => { if (messageSearch.opened && active) conversationSearchBar.edit(); });
  }
  function cancelSearchNavigation() {
    if (!locatingSearchResult) return;
    if (beeperData.currentChatID === locatingSearchChatID && beeperData.targetMessageID === pendingOpenMessageID)
      beeperData.targetMessageID = "";
    locatingSearchResult = false;
    locatingSearchChatID = ""; pendingOpenMessageID = ""; targetPageCount = 0;
  }
  function closeConversationSearch(restoreFocus = true) {
    cancelSearchNavigation(); messageSearch.close();
    if (restoreFocus && active) focusNavigation();
  }
  function acceptConversationSearch() {
    navigation = "messages"; navigationFocus.forceActiveFocus(); messageSearch.accept();
  }
  function revealSearchMatch(message) {
    if (!active || !messageSearch.opened || message.chatID !== beeperData.currentChatID) return;
    messageWheel.reset(); messageList.cancelFlick(); pinLatest = false; restoringView = false;
    locatingSearchResult = true; locatingSearchChatID = message.chatID; targetPageCount = 0;
    beeperData.messagesPaginationBlocked = false;
    pendingOpenMessageID = message.id;
    // Follow only public history cursors, never synthesize one from an ID or
    // sortKey. A search target may be older than the notification paging limit.
    beeperData.selectChat(message.chatID, message.id);
  }
  function cycleNetwork(direction) {
    const filters = ["all", "telegram", "whatsapp", "instagram", "sms"];
    closeChatSearch();
    const index = Math.max(0, filters.indexOf(networkFilter));
    beeperData.networkFilter = filters[(index + direction + filters.length) % filters.length];
    const selected = filteredChats.findIndex(chat => chat.id === beeperData.currentChatID);
    if (filteredChats.length) chooseChat(selected >= 0 ? selected : 0);
    else { rememberPosition(); editMessageID = ""; messageIndex = -1; beeperData.clearSelection(); }
    navigation = "chats"; navigationFocus.forceActiveFocus();
  }
  function toggleUnreadFirst() {
    if (!canCycleNetwork) return;
    gPending = false;
    beeperData.unreadFirst = !unreadFirst;
    syncChatIndex();
    // Reorder the sidebar without reopening the chat or touching its draft,
    // message selection or read state. Reveal the new start of the list.
    Qt.callLater(sidebar.revealFirstChat);
    schedulePagination();
  }
  function toggleArchiveView() {
    if (!active || !windowFocused || modal || recording || preparingRecording || messageSearch.opened) return;
    rememberPosition(); gPending = false;
    beeperData.showArchived = !showArchived;
    const index = filteredChats.findIndex(chat => chat.id === beeperData.currentChatID);
    if (index >= 0) { chatIndex = index; sidebar.revealChat(index); }
    else if (filteredChats.length) chooseChat(chatIndex);
    else { editMessageID = ""; messageIndex = -1; beeperData.clearSelection(); }
    focusNavigation(); schedulePagination();
  }
  function toggleSelectedArchive() {
    if (!active || !windowFocused || modal || recording || preparingRecording || messageSearch.opened || !beeperData.currentChat) return;
    rememberPosition();
    beeperData.setChatArchived(beeperData.currentChatID, !beeperData.currentChat.isArchived);
  }
  function reconcileArchiveSelection() {
    if (!active || !beeperData?.currentChat || Format.isChatInView(beeperData.currentChat, showArchived)) return;
    if (filteredChats.length) chooseChat(chatIndex);
    else { editMessageID = ""; messageIndex = -1; beeperData.clearSelection(); }
    focusNavigation();
  }
  function openChat(chatID, messageID) { closeConversationSearch(false); pinLatest = false; pendingOpenMessageID = messageID || ""; beeperData.selectChat(chatID, messageID || ""); navigation = "messages"; }
  function chooseChat(index) {
    if (!filteredChats.length) return;
    chatIndex = Math.max(0, Math.min(filteredChats.length - 1, index));
    rememberPosition();
    if (recording) stopRecording();
    editMessageID = ""; beeperData.selectChat(filteredChats[chatIndex].id); messageIndex = -1;
    sidebar.revealChat(chatIndex);
  }
  function moveMessageSelection(delta) {
    if (!beeperData.messages.length) return;
    messageWheel.reset();
    messageList.cancelFlick();
    restoringView = false;
    pinLatest = false;
    messageIndex = messageIndex < 0 || navigation !== "messages" ? beeperData.messages.length - 1
      : Math.max(0, Math.min(beeperData.messages.length - 1, messageIndex + delta));
    navigation = "messages";
    navigationFocus.forceActiveFocus();
    messageList.positionViewAtIndex(messageIndex, ListView.Contain);
    rememberPosition();
  }
  function goEdge(last) {
    messageWheel.reset();
    restoringView = false;
    pinLatest = false;
    if (navigation === "chats") chooseChat(last ? filteredChats.length - 1 : 0);
    else {
      messageIndex = last ? beeperData.messages.length - 1 : 0;
      messageList.positionViewAtIndex(messageIndex, ListView.Contain);
      rememberPosition();
      if (!last && beeperData.hasOlderMessages) beeperData.loadMessages(true);
    }
  }
  function compose() { if (composerSurface.enabled && beeperData.currentChatID) { navigation = "compose"; composer.forceActiveFocus(); } }
  function openModal(name) {
    if (name !== "help" && name !== "media") return;
    modal = name;
    if (photoPreviewOpen && externalPhotoPreview) return;
    Qt.callLater(() => modalSurface.forceActiveFocus());
  }
  function closeModal() { modal = ""; navigationFocus.forceActiveFocus(); }
  function submitMessage() {
    if (recording || preparingRecording || composer.inputMethodComposing) return;
    if (editMessageID) {
      const id = editMessageID, chatID = beeperData.currentChatID, text = composer.text;
      beeperData.request("edit", {chatID: chatID, messageID: id, text: text}, (result, error) => {
        if (!error && chatID === beeperData.currentChatID) { editMessageID = ""; editText = ""; beeperData.loadMessages(false); }
      });
    } else beeperData.sendMessage();
  }
  function replyToSelectedMessage() {
    if (!selectedMessage || !Format.supports(beeperData.currentChat, "reply")) return;
    beeperData.replyToMessageID = selectedMessage.id; compose();
  }
  function editSelectedMessage() {
    if (!selectedMessage?.isSender || !Format.supports(beeperData.currentChat, "edit", selectedMessage)) return;
    editText = Format.text(selectedMessage); editMessageID = selectedMessage.id; compose();
  }
  function reactToSelectedMessage(reaction) {
    beeperData.toggleMessageReaction(selectedMessage, reaction);
  }
  function activateSelectedMedia() {
    const messageID = selectedMessage?.id, chatID = beeperData.currentChatID;
    if (!messageID) return;
    messageList.positionViewAtIndex(messageIndex, ListView.Contain);
    // Reveal the selected row first so its viewport-managed player is loaded.
    Qt.callLater(() => {
      if (!active || !windowFocused || modal || composer.activeFocus || searchField.activeFocus || conversationSearchBar.input.activeFocus
          || beeperData.currentChatID !== chatID || selectedMessage?.id !== messageID) return;
      messageList.itemAtIndex(messageIndex)?.activateMedia();
    });
  }
  function startRecording() {
    if (beeperData.demo) { beeperData.lastError = "The design preview does not activate the microphone."; return; }
    if (recording || preparingRecording || !beeperData.currentChatID) return;
    preparingRecording = true; recordingChatID = beeperData.currentChatID;
    beeperData.request("prepareRecording", {}, (result, error) => {
      preparingRecording = false;
      if (error || !result) return;
      if (!active || recordingChatID !== beeperData.currentChatID) { beeperData.request("discardAttachment", {path: result.path}); return; }
      recordingAttachment = result;
      recorder = recorderComponent.createObject(root, {outputPath: result.path});
      recorder.start();
    });
  }
  function stopRecording() { if (recorder) recorder.stop(); }
  function userHistoryScroll() {
    cancelSearchNavigation();
    pinLatest = false; restoringView = false; historyWheelTimer.restart();
    Qt.callLater(rememberPosition);
  }
  function keepLatestVisible() {
    if (!active || !pinLatest) return;
    messageList.forceLayout(); messageList.positionViewAtEnd(); updateView();
  }
  function changeTextSize(steps) {
    const size = steps === 0 ? Theme.beeperFont.body : beeperData.chatTextSize + steps * 2;
    if (Math.max(14, Math.min(36, size)) === beeperData.chatTextSize) return;
    rememberPosition();
    restoringView = true;
    beeperData.setChatTextSize(size);
    Qt.callLater(restorePosition);
  }
  function zoomWheel(angleDelta, pixelDelta) {
    // Accumulate high-resolution wheels/trackpads into normal text-size steps.
    zoomWheelRemainder += angleDelta ? angleDelta / 120 : pixelDelta / 60;
    const steps = Math.trunc(zoomWheelRemainder);
    if (steps) { zoomWheelRemainder -= steps; changeTextSize(steps); }
  }
  // Throttle, do not debounce: start fetching before the reader reaches the
  // boundary even when wheel/trackpad events keep arriving continuously.
  function schedulePagination() { if (active && !paginationTimer.running) paginationTimer.start(); }
  function paginateVisibleLists() {
    if (!active || !beeperData.connected || connectionSurface.visible) return;
    const remaining = chatList.originY + chatList.contentHeight - chatList.contentY - chatList.height;
    // Unread-first also needs older pages: an old unread conversation must
    // reach the top without requiring a scroll through all the read chats.
    if (!beeperData.loading && beeperData.hasMoreChats && !beeperData.chatsPaginationBlocked && (unreadFirst || remaining < 188))
      beeperData.refreshChats(true);
    if (!restoringView && !pendingOpenMessageID && !beeperData.targetMessageID
        && !beeperData.loadingMessages && beeperData.hasOlderMessages
        && messageList.contentY - messageList.originY < 180)
      beeperData.loadMessages(true);
  }
  function rememberPosition() {
    if ((!active && beeperData.viewOwner !== root) || !displayedChatID || !messageList.count || restoringView) return;
    const index = Math.max(0, messageList.indexAt(1, messageList.contentY + 12)), item = messageList.itemAtIndex(index);
    beeperData.viewPositions[displayedChatID] = {atLatest: pinLatest || messageList.atYEnd, messageID: beeperData.messages[index]?.id || "", offset: item ? messageList.contentY - item.y : 0, contentY: messageList.contentY};
  }
  function restorePosition() {
    if (!active) return;
    if (historyInteracting && !pinLatest && displayedChatID === beeperData.currentChatID) {
      restoringView = false; updateView(); return;
    }
    restoringView = true;
    if (beeperData.loadingMessages && !beeperData.messages.length) return;
    messageList.forceLayout();
    const saved = beeperData.viewPositions[beeperData.currentChatID];
    const index = saved ? beeperData.messages.findIndex(message => message.id === saved.messageID) : -1;
    if (saved && !saved.atLatest) {
      pinLatest = false;
      if (index >= 0) {
        messageList.positionViewAtIndex(index, ListView.Beginning);
        const item = messageList.itemAtIndex(index);
        if (item) messageList.contentY = item.y + (saved.offset || 0);
      } else messageList.contentY = saved.contentY || messageList.originY;
    } else messageList.positionViewAtEnd();
    displayedChatID = beeperData.currentChatID;
    Qt.callLater(() => { restoringView = false; updateView(); schedulePagination(); });
  }
  function updateView() {
    if (!beeperData || !messageList) return;
    if (active) {
      beeperData.viewOwner = root;
      beeperData.viewFocused = !restoringView && windowFocused && modal !== "media" && !connectionSurface.visible;
      beeperData.viewAtLatest = !restoringView && messageList.atYEnd;
    } else if (beeperData.viewOwner === root) { beeperData.viewOwner = null; beeperData.viewFocused = false; }
  }
  onActiveChanged: {
    if (!active) { rememberPosition(); clearMessageSelection(); closeConversationSearch(false); messageWheel.reset(); messageList.cancelFlick(); historyWheelTimer.stop(); pinLatest = false; stopRecording(); beeperData.flushDraft(); modal = ""; closeChatSearch(); }
    else { reconcileArchiveSelection(); restoringView = true; Qt.callLater(ensureInitialChat); Qt.callLater(restorePosition); }
    updateView(); schedulePagination();
  }
  onWindowFocusedChanged: {
    if (!windowFocused && !modal && !emojiPickerOpen) clearMessageSelection();
    updateView();
  }
  onModalChanged: updateView()
  onFilteredChatsChanged: { syncChatIndex(); schedulePagination(); Qt.callLater(ensureInitialChat); }
  Connections {
    target: root.composer
    function onActiveFocusChanged() {
      if (root.composer.activeFocus) { root.clearMessageSelection(); root.navigation = "compose"; }
    }
  }
  Connections {
    target: root.beeperData
    function onChatArchiveChanged(chatID, archived) {
      if (root.beeperData.currentChatID === chatID) root.reconcileArchiveSelection();
    }
    function onMessageSent(chatID) {
      if (!root.active || root.beeperData.currentChatID !== chatID) return;
      root.clearMessageSelection();
      root.closeConversationSearch(false);
      root.pinLatest = true;
      messageWheel.reset();
      root.pendingOpenMessageID = ""; root.beeperData.targetMessageID = ""; root.targetPageCount = 0;
      // Move now, including if an older page is in flight. The following refresh
      // then remembers an end anchor and follows the newly accepted message.
      messageList.cancelFlick(); messageList.forceLayout(); messageList.positionViewAtEnd();
      root.updateView();
      Qt.callLater(root.restorePosition);
    }
    function onTokenStored() { tokenField.text = ""; }
    function onQuotesUpdating() {
      if (!root.active) return;
      if (root.historyInteracting) messageList.captureMovingAnchor();
      else { root.rememberPosition(); root.restoringView = true; }
    }
    function onQuotesUpdated() {
      if (!root.active) return;
      if (root.restoringView) Qt.callLater(root.restorePosition);
      else messageWheel.shiftOrigin(messageList.takeAnchorShift());
    }
    function onLoadingChanged() { root.schedulePagination(); }
    function onLoadingMessagesChanged() {
      root.schedulePagination();
      if (root.locatingSearchResult && !root.beeperData.loadingMessages && root.beeperData.messagesPaginationBlocked) {
        root.cancelSearchNavigation();
        messageSearch.errorText = "Could not load the matching message. Press Enter to retry.";
      }
    }
    function onConnectedChanged() { root.schedulePagination(); Qt.callLater(root.ensureInitialChat); }
    function onMessagesUpdating() {
      if (!root.active) return;
      root.selectedMessageIDBeforeUpdate = root.selectedMessage?.id || "";
      if (root.historyInteracting) messageList.captureMovingAnchor();
      else { root.rememberPosition(); root.restoringView = true; }
    }
    function onCurrentChatIDChanged() {
      root.closeConversationSearch(false);
      root.messageIndex = -1; root.selectedMessageIDBeforeUpdate = "";
      root.syncChatIndex();
      Qt.callLater(root.ensureInitialChat);
      if (root.active) { root.rememberPosition(); root.restoringView = true; }
      messageWheel.reset(); messageList.cancelFlick(); historyWheelTimer.stop(); root.pinLatest = false;
    }
    function onMessagesLoaded(older) {
      if (!root.active) return;
      if (root.selectedMessageIDBeforeUpdate) {
        root.messageIndex = root.beeperData.messages.findIndex(message => message.id === root.selectedMessageIDBeforeUpdate);
        root.selectedMessageIDBeforeUpdate = "";
      }
      const wanted = root.pendingOpenMessageID || root.beeperData.targetMessageID || "";
      if (wanted) root.pinLatest = false;
      const index = wanted ? root.beeperData.messages.findIndex(message => message.id === wanted) : -1;
      if (index >= 0) { root.messageIndex = index; messageList.positionViewAtIndex(index, ListView.Center); root.pendingOpenMessageID = ""; root.beeperData.targetMessageID = ""; root.targetPageCount = 0; root.locatingSearchResult = false; root.restoringView = false; }
      else if (wanted && root.beeperData.hasOlderMessages && !root.beeperData.messagesPaginationBlocked
          && (root.locatingSearchResult || root.targetPageCount < 20)) {
        ++root.targetPageCount;
        const chatID = root.beeperData.currentChatID;
        Qt.callLater(() => {
          if (root.active && root.beeperData.currentChatID === chatID
              && (root.pendingOpenMessageID || root.beeperData.targetMessageID) === wanted)
            root.beeperData.loadMessages(true);
        });
      }
      else if (wanted) {
        if (root.locatingSearchResult) messageSearch.errorText = "This message is no longer available in the conversation.";
        else root.beeperData.lastError = "This message is not available in the loaded history.";
        root.pendingOpenMessageID = ""; root.beeperData.targetMessageID = ""; root.targetPageCount = 0;
        root.locatingSearchResult = false; root.restoringView = false;
      }
      else if (root.restoringView || root.pinLatest || root.displayedChatID !== root.beeperData.currentChatID) Qt.callLater(root.restorePosition);
      else messageWheel.shiftOrigin(messageList.takeAnchorShift());
      root.displayedChatID = root.beeperData.currentChatID;
      root.schedulePagination();
    }
  }
  Timer { id: gTimer; interval: 650; onTriggered: root.gPending = false }
  Timer { id: paginationTimer; interval: 100; onTriggered: root.paginateVisibleLists() }
  Timer { id: historyWheelTimer; interval: 160 }
  BeeperSearchController {
    id: messageSearch; beeperData: root.beeperData
    onMatchRequested: message => root.revealSearchMatch(message)
    onInvalidated: root.cancelSearchNavigation()
  }
  Component {
    id: recorderComponent
    BeeperRecorder {
      onFinished: path => {
        if (root.recordingChatID === root.beeperData.currentChatID) root.beeperData.draftAttachment = root.recordingAttachment;
        else root.beeperData.request("saveDraft", {chatID: root.recordingChatID, text: root.beeperData.localDrafts[root.recordingChatID]?.text || "", attachment: root.recordingAttachment});
        root.recorder = null; destroy();
      }
      onFailed: message => { root.beeperData.lastError = message; root.recorder = null; destroy(); }
    }
  }
  Item { id: navigationFocus; focus: true }
  Shortcut {
    sequence: "Ctrl+/"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.active && root.windowFocused && !root.modal && !connectionSurface.visible
      && !composerSurface?.emojiPickerOpen
      && !!root.beeperData.currentChatID && !root.composer.inputMethodComposing && !root.recording && !root.preparingRecording
    onActivated: root.openConversationSearch()
  }
  Shortcut {
    sequence: "Tab"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.canCycleNetwork
    onActivated: root.cycleNetwork(1)
  }
  Shortcut {
    sequence: "Shift+Tab"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.canCycleNetwork
    onActivated: root.cycleNetwork(-1)
  }
  Shortcut {
    sequence: "Ctrl+J"; context: Qt.WindowShortcut
    enabled: root.canNavigateMessages
    onActivated: messageSearch.opened ? messageSearch.move(1) : root.moveMessageSelection(1)
  }
  Shortcut {
    sequence: "Ctrl+K"; context: Qt.WindowShortcut
    enabled: root.canNavigateMessages
    onActivated: messageSearch.opened ? messageSearch.move(-1) : root.moveMessageSelection(-1)
  }
  Shortcut {
    sequences: ["Ctrl++", "Ctrl+=", "Ctrl+Shift++", "Ctrl+Shift+="]
    context: Qt.WindowShortcut; enabled: root.canZoomText
    onActivated: root.changeTextSize(1)
  }
  Shortcut {
    sequence: "Ctrl+-"; context: Qt.WindowShortcut; enabled: root.canZoomText
    onActivated: root.changeTextSize(-1)
  }
  Shortcut {
    sequence: "Ctrl+0"; context: Qt.WindowShortcut; enabled: root.canZoomText
    onActivated: root.changeTextSize(0)
  }
  Keys.onPressed: event => {
    if (!root.active || !root.windowFocused) return;
    if (composerSurface.emojiPickerOpen) {
      if (event.key === Qt.Key_Escape) composerSurface.closeEmojiPicker(true);
      event.accepted = true; return;
    }
    if (event.key === Qt.Key_Escape) {
      if (modal) closeModal();
      else if (messageSearch.opened) closeConversationSearch();
      else if (searchOpen) { closeChatSearch(); navigation = "chats"; }
      else if (beeperData.replyToMessageID || editMessageID) { beeperData.replyToMessageID = ""; editMessageID = ""; }
      else if (beeperData.draftAttachment) beeperData.clearAttachment();
      else if (composer.activeFocus || navigation === "messages" || navigation === "compose") focusNavigation();
      else if (showArchived) toggleArchiveView();
      else closeRequested();
      event.accepted = true; return;
    }
    if (connectionSurface.visible || modal || composer.activeFocus || searchField.activeFocus || tokenField.activeFocus || conversationSearchBar.input.activeFocus) return;
    const key = event.text || (event.key >= Qt.Key_A && event.key <= Qt.Key_Z ? String.fromCharCode(event.key + (event.modifiers & Qt.ShiftModifier ? 0 : 32)) : "");
    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_D || event.key === Qt.Key_U)) {
      messageWheel.reset();
      pinLatest = false;
      const list = navigation === "chats" ? chatList : messageList;
      list.flickTo(Qt.point(list.contentX, Math.max(list.originY, Math.min(list.originY + list.contentHeight - list.height, list.contentY + list.height * (event.key === Qt.Key_D ? 0.5 : -0.5))))); event.accepted = true;
    } else if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
    else if (messageSearch.opened && ["n", "N", "j", "k"].includes(key)) {
      const previous = key === "N" || key === "k" || (event.key === Qt.Key_N && (event.modifiers & Qt.ShiftModifier));
      messageSearch.move(previous ? -1 : 1); event.accepted = true;
    }
    else if (messageSearch.opened && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) { acceptConversationSearch(); event.accepted = true; }
    else if (!messageSearch.opened && key === "u" && !(event.modifiers & Qt.ShiftModifier)) {
      if (!event.isAutoRepeat) toggleUnreadFirst();
      event.accepted = true;
    }
    else if (!messageSearch.opened && (key === "a" || key === "A")) {
      if (!event.isAutoRepeat) {
        if (key === "A" || (event.modifiers & Qt.ShiftModifier)) toggleSelectedArchive();
        else toggleArchiveView();
      }
      event.accepted = true;
    }
    else if (key === "j" || key === "k") { chooseChat(chatIndex + (key === "j" ? 1 : -1)); focusNavigation(); event.accepted = true; }
    else if (key === "h" || key === "l") { key === "h" ? focusNavigation() : moveMessageSelection(0); event.accepted = true; }
    else if (key === "g") { if (gPending) { goEdge(false); gPending = false; } else { gPending = true; gTimer.restart(); } event.accepted = true; }
    else if (key === "G") { goEdge(true); event.accepted = true; }
    else if (key === "/") { openChatSearch(); event.accepted = true; }
    else if (key === "?") { openModal("help"); event.accepted = true; }
    else if (key === "m" && beeperData.currentChatID) { if (!event.isAutoRepeat) beeperData.markChatRead(beeperData.currentChatID); event.accepted = true; }
    else if (key === "n" && beeperData.currentChatID) { if (!event.isAutoRepeat) beeperData.markChatUnread(beeperData.currentChatID); event.accepted = true; }
    else if (key === "r" && selectedMessage) { replyToSelectedMessage(); event.accepted = true; }
    else if (key === "e" && selectedMessage?.isSender) { editSelectedMessage(); event.accepted = true; }
    else if (key === "o" && selectedMessage?.attachments?.length) { previewAttachment = selectedMessage.attachments[0]; openModal("media"); event.accepted = true; }
    else if (event.key === Qt.Key_Space && selectedMessage) { if (!event.isAutoRepeat) activateSelectedMedia(); event.accepted = true; }
    else if (/^[1-5]$/.test(key) && selectedMessage) { if (!event.isAutoRepeat) reactToSelectedMessage(quickReactions[Number(key) - 1]); event.accepted = true; }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { compose(); event.accepted = true; }
  }

  RowLayout {
    anchors { fill: parent; margins: 20 }
    spacing: 0
    BeeperSidebar {
      id: sidebar
      enabled: root.active && !root.modal && !connectionSurface.visible
      Layout.preferredWidth: root.compact ? 232 : 338
      Layout.fillHeight: true
      chats: root.filteredChats
      currentNetwork: root.currentNetwork
      showArchived: root.showArchived
      unreadFirst: root.unreadFirst
      accountConnectionIssues: root.beeperData.accountConnectionIssues
      serviceConnectionIssue: root.beeperData.serviceConnectionIssue
      currentChatID: root.beeperData.currentChatID
      unreadCount: root.beeperData.unreadConversationCount(root.networkFilter)
      unreadReady: root.beeperData.unreadCountsReady
      unreadLoading: root.beeperData.loadingUnreadCounts
      searchOpen: root.searchOpen
      onNetworkCycleRequested: root.cycleNetwork(1)
      onSearchAccepted: { root.chooseChat(0); root.closeChatSearch(); root.navigation = "messages"; }
      onChatSelected: index => { root.chooseChat(index); root.navigation = "chats"; navigationFocus.forceActiveFocus(); }
      onViewportChanged: root.schedulePagination()
    }

    ColumnLayout {
      id: conversationColumn
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: root.compact ? 14 : 25
      spacing: 0
      RowLayout {
        id: conversationHeader
        objectName: "beeperConversationHeader"
        Layout.fillWidth: true; Layout.preferredHeight: 82
        spacing: 12
        BeeperAvatar {
          objectName: "beeperHeaderAvatar"
          connectionProblem: !!root.conversationConnectionIssue
          visible: root.beeperData.currentChat !== null
          Layout.preferredWidth: diameter; Layout.preferredHeight: diameter
          diameter: 56
          chat: root.beeperData.currentChat
        }
        ColumnLayout {
          Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 5
          Text { objectName: "beeperChatTitle"; Layout.fillWidth: true; text: Format.chatTitle(root.beeperData.currentChat); elide: Text.ElideRight; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.title; weight: Font.DemiBold } }
          Text { objectName: "beeperChatSubtitle"; Layout.fillWidth: true; visible: !!text; text: Format.chatSubtitle(root.beeperData.currentChat); elide: Text.ElideRight; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
        }
        BeeperSearchBar {
          id: conversationSearchBar
          Layout.preferredWidth: Math.min(360, conversationHeader.width / 2)
          Layout.minimumWidth: 0
          Layout.alignment: Qt.AlignVCenter
          controller: messageSearch
          accent: root.conversationAccent
          locating: root.locatingSearchResult
          onAcceptRequested: root.acceptConversationSearch()
          onCloseRequested: root.closeConversationSearch()
        }
      }
      Item {
        Layout.fillWidth: true; Layout.fillHeight: true
        enabled: !connectionSurface.visible
        BeeperHistory {
          id: messageList; objectName: "beeperMessages"
          anchors { fill: parent; topMargin: 14; bottomMargin: 12 }
          clip: true
          model: KeyedListModel { rows: root.beeperData.messages }
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          acceptedButtons: Qt.NoButton
          AcceleratedScroll { id: messageWheel; flickable: messageList; inputEnabled: root.active && !root.modal }
          ScrollBar.vertical: ScrollBar { id: historyScrollBar; objectName: "beeperHistoryScrollBar"; policy: ScrollBar.AsNeeded; onPressedChanged: if (pressed) { root.userHistoryScroll(); messageWheel.reset(); } }
          onAtYEndChanged: root.updateView()
          onMovementStarted: { root.pinLatest = false; root.restoringView = false; }
          onContentYChanged: root.schedulePagination()
          onContentHeightChanged: { root.schedulePagination(); Qt.callLater(root.keepLatestVisible); }
          onHeightChanged: { root.schedulePagination(); Qt.callLater(root.keepLatestVisible); }
          header: Item {
            width: messageList.width; height: root.beeperData.hasOlderMessages ? 12 : 30
            Text { anchors.centerIn: parent; visible: !root.beeperData.hasOlderMessages; text: root.beeperData.messages.length ? Format.dateLabel(root.beeperData.messages[0].timestamp) : ""; color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
          }
          delegate: BeeperMessage {
            required property var row
            required property int index
            width: messageList.width
            message: row; beeperData: root.beeperData
            networkAccent: root.conversationAccent
            searchQuery: messageSearch.opened ? messageSearch.query : ""
            textScale: root.beeperData.chatTextSize / Theme.beeperFont.body
            selected: index === root.messageIndex
            playbackEnabled: root.active && !root.videoPreviewOpen
            viewportReady: false
            renderMedia: viewportReady && root.visible && y + height >= messageList.contentY - messageList.height / 2
              && y <= messageList.contentY + messageList.height * 1.5
            onSelectedRequested: { root.messageIndex = index; root.navigation = "messages"; navigationFocus.forceActiveFocus(); }
            onPreviewRequested: attachment => { root.previewAttachment = attachment; root.openModal("media"); }
          }
        }
        Column {
          visible: !connectionSurface.visible && (!root.beeperData.currentChatID || (root.beeperData.messages.length === 0 && !root.beeperData.loadingMessages))
          anchors.centerIn: parent; width: Math.min(parent.width - 40, 340); spacing: 15
          Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰍡"; color: Qt.alpha(Theme.sideApplications, 0.6); font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.illustration } }
          Text { width: parent.width; text: root.beeperData.currentChatID ? "The conversation starts here." : "Everyone,\nin one place."; horizontalAlignment: Text.AlignHCenter; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.subheading; weight: Font.Medium } wrapMode: Text.Wrap }
          Text { width: parent.width; text: root.beeperData.currentChatID ? "Write the first message." : "Choose a conversation, or check in with someone."; horizontalAlignment: Text.AlignHCenter; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control } wrapMode: Text.Wrap }
        }
      }
      Rectangle {
        Layout.fillWidth: true; Layout.bottomMargin: 10
        implicitHeight: errorText.implicitHeight + 18
        visible: !!root.beeperData.lastError && !connectionSurface.visible
        color: Qt.alpha(Theme.error, 0.09); radius: 10
        Text { id: errorText; anchors { left: parent.left; right: dismissError.left; verticalCenter: parent.verticalCenter; margins: 10 } text: root.beeperData.lastError; color: Theme.error; wrapMode: Text.Wrap; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
        BeeperButton { id: dismissError; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: "×"; onClicked: root.beeperData.lastError = "" }
      }
      BeeperComposer {
        id: composerSurface
        Layout.fillWidth: true
        enabled: !connectionSurface.visible && !!root.beeperData.currentChatID && !root.beeperData.currentChat?.isReadOnly
        beeperData: root.beeperData
        networkAccent: root.conversationAccent
        textSize: root.beeperData.chatTextSize
        active: root.active
        dictating: root.dictating
        compact: root.compact
        editMessageID: root.editMessageID
        editText: root.editText
        recording: root.recording
        preparingRecording: root.preparingRecording
        recordingDuration: root.recorder?.duration || 0
        onEditTextEdited: text => root.editText = text
        onDraftTextEdited: text => root.beeperData.draftText = text
        onSubmitRequested: root.submitMessage()
        onPasteAttachmentRequested: root.beeperData.pasteAttachment()
        onRecordingToggleRequested: root.recording ? root.stopRecording() : root.startRecording()
        onAttachmentDropped: url => root.beeperData.stageAttachment(url)
      }
    }
  }

  // Claim Ctrl+wheel before the message/composer Flickables consume it.
  // No MouseArea: clicks and ordinary scrolling pass straight through.
  Item {
    anchors { top: parent.top; bottom: parent.bottom; right: parent.right; margins: 20 }
    width: conversationColumn.width
    WheelHandler {
      target: null
      enabled: root.active && !root.modal
      acceptedModifiers: Qt.NoModifier
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      blocking: false
      onWheel: event => { root.userHistoryScroll(); event.accepted = false; }
    }
    WheelHandler {
      objectName: "beeperTextZoom"
      target: null
      enabled: root.canZoomText
      acceptedModifiers: Qt.ControlModifier
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: event => { root.zoomWheel(event.angleDelta.y, event.pixelDelta.y); event.accepted = true; }
    }
  }

  BeeperConnection {
    id: connectionSurface
    anchors.centerIn: parent
    width: Math.max(0, Math.min(implicitWidth, parent.width - 48))
    height: Math.max(0, Math.min(implicitHeight, parent.height - 180))
    beeperData: root.beeperData
    active: root.active && root.windowFocused
    onVisibleChanged: {
      if (visible) { root.modal = ""; root.closeConversationSearch(false); }
      root.updateView();
      if (!visible && root.active && root.windowFocused) root.focusNavigation();
    }
    onConnectRequested: token => root.beeperData.connectToken(token)
    onRetryRequested: root.beeperData.retryConnection()
    onCloseRequested: root.closeRequested()
  }

  BeeperDialogs {
    id: dialogs
    anchors.fill: parent
    beeperData: root.beeperData
    mode: root.modal
    active: root.active
    previewAttachment: root.previewAttachment
    externalPhotoPreview: root.externalPhotoPreview
    onCloseRequested: root.closeModal()
  }
}
