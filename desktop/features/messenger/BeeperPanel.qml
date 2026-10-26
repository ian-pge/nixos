import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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
  property var pendingReadNavigation: null
  property int messageIndex: -1
  readonly property string networkFilter: beeperData.networkFilter
  readonly property bool showLowPriority: beeperData.showLowPriority
  readonly property bool unreadFirst: beeperData.unreadFirst
  readonly property var currentNetwork: Format.networkBadge(networkFilter)
  // The filter logo describes the view; conversation controls describe its
  // actual platform, including when the view contains every network.
  readonly property string conversationConnectionIssue: Format.chatConnectionIssue(beeperData.currentChat, beeperData.accountConnectionIssues, beeperData.serviceConnectionIssue)
  readonly property color conversationAccent: conversationConnectionIssue ? Theme.error : Theme.beeperNetworkColors[Format.networkBadge(beeperData.currentChat?.network).key] || Theme.secondary
  property bool searchOpen: false
  property string searchChatID: ""
  property bool locatingSearchResult: false
  property string locatingSearchChatID: ""
  property string modal: ""
  property string editMessageID: ""
  property string editText: ""
  property var previewAttachment: null
  property Item previewOrigin: null
  // Where the viewed attachment sits in the history, for h / l in the viewer.
  property string previewMessageID: ""
  property int previewAttachmentIndex: -1
  property int pendingPreviewStep: 0
  property int previewPagesLeft: 0
  property var attachmentChoices: []
  property string attachmentChoiceMessageID: ""
  property string replyTargetID: ""
  // Tests replace the system clipboard.
  property var clipboardWriter: text => { Quickshell.clipboardText = text; }
  property var linkOpener: url => Qt.openUrlExternally(url)
  // The message holding a mouse text selection; only one at a time.
  property Item textSelectionOwner: null
  readonly property string selectedText: textSelectionOwner?.selectedText ?? ""
  property string notice: ""
  // Vim-style modal editing in the composer; hosts opt in.
  property bool vimEditing: false
  property bool externalPhotoPreview: false
  readonly property bool photoPreviewOpen: modal === "media"
    && ["image", "gif", "video"].includes(Format.attachmentType(previewAttachment || {}))
  readonly property bool videoPreviewOpen: modal === "media" && Format.attachmentType(previewAttachment || {}) === "video"
  readonly property bool imageEditorOpen: modal === "draw"
  property string imageEditChatID: ""
  property int imageEditIndex: -1
  property var imageEditOriginal: null
  property var recordingAttachment: null
  property string recordingChatID: ""
  property bool preparingRecording: false
  property int recordingGeneration: 0
  property bool recordingCancelled: false
  property var recorder: null
  property Component recorderFactory: recorderComponent
  property var attachmentPicker: null
  property Component attachmentPickerFactory: attachmentPickerComponent
  // A host may hold the picker until its closing animation has finished.
  property bool attachmentPickerReady: true
  property bool attachmentPickerStarted: false
  onAttachmentPickerReadyChanged: if (attachmentPickerReady) Qt.callLater(startAttachmentPicker)
  readonly property bool canNavigatePanes: active && windowFocused && !modal && !connectionSurface.visible
    && !attachmentPicker && !composer.inputMethodComposing && !searchField.inputMethodComposing
  readonly property bool canPickAttachment: canUseComposerShortcuts && composer.activeFocus
    && !beeperData.currentChat?.isReadOnly && !beeperData.sending && !editMessageID
    && !recording && !preparingRecording && !attachmentPicker && !emojiPickerOpen && !beeperData.stagingAttachments
  property bool gPending: false
  property string pendingOpenMessageID: ""
  property string displayedChatID: ""
  property int targetPageCount: 0
  property bool restoringView: false
  property bool historyUpdatePending: false
  property var arrivalBaseline: null
  property string arrivalReadyChatID: ""
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
  readonly property var filteredChats: Format.orderChats(beeperData.chats.filter(chat => Format.isChatInView(chat, showLowPriority)
    && (networkFilter === "all" || Format.networkBadge(chat.network).key === networkFilter)
    && (!searchField.text || (Format.chatTitle(chat) + " " + Format.preview(chat, beeperData.chatPreviews)).toLowerCase().includes(searchField.text.toLowerCase()))), unreadFirst)
  readonly property bool canCycleNetwork: active && windowFocused && !modal && !beeperData.tokenRequired
    && !composerSurface?.emojiPickerOpen
    && !(connectionSurface?.visible ?? true)
    && !composer?.activeFocus && !searchField?.activeFocus && !tokenField?.activeFocus
    && !recording && !preparingRecording && !searchOpen && !messageSearch.opened
  readonly property bool canZoomText: active && windowFocused && !modal
    && !composerSurface?.emojiPickerOpen
    && !connectionSurface.visible
  readonly property bool canUseMessageShortcuts: active && windowFocused && !modal && !connectionSurface.visible
    && !attachmentPicker && !emojiPickerOpen
    && !composer.activeFocus && !searchField.activeFocus && !tokenField.activeFocus
    && !conversationSearchBar.input.activeFocus
  readonly property bool canSeekAudio: canUseMessageShortcuts && !!beeperData.audioPlayback?.playing
  readonly property bool canNavigateSearchChats: active && windowFocused && searchOpen && !modal
    && !connectionSurface.visible && !composerSurface?.emojiPickerOpen && !attachmentPicker
    && !searchField.inputMethodComposing && !composer.inputMethodComposing
  readonly property bool canNavigateMessages: active && windowFocused && !modal && !searchOpen
    && !messageList.loading
    && !composerSurface?.emojiPickerOpen
    && !connectionSurface.visible && !searchField.activeFocus && !tokenField.activeFocus
    && !conversationSearchBar.input.activeFocus
    && !composer.inputMethodComposing && !!beeperData.currentChatID
  readonly property var quickReactions: Format.quickReactions(beeperData.currentChat)
  readonly property bool canUseComposerShortcuts: active && windowFocused && !modal && !connectionSurface.visible
    && !!beeperData.currentChatID && !searchOpen && !messageSearch.opened
    && !composer.inputMethodComposing && !tokenField.activeFocus
  readonly property bool canStartRecording: active && beeperData.connected && !!beeperData.currentChatID
    && !beeperData.currentChat?.isReadOnly && !beeperData.sending && !beeperData.draftAttachment && !beeperData.stagingAttachments
    && !editMessageID && !dictating && !recorder && !preparingRecording && !composer.inputMethodComposing
  signal closeRequested()
  signal nativeDialogOpened()
  signal nativeDialogClosed()
  implicitWidth: 1280
  implicitHeight: 900
  clip: true

  function clearMessageSelection() { messageIndex = -1; selectedMessageIDBeforeUpdate = ""; }
  function focusNavigation() { if (!active) return; cancelReplyNavigation(); clearMessageSelection(); navigation = "chats"; if (connectionSurface.visible) connectionSurface.focusInput(true); else navigationFocus.forceActiveFocus(); }
  function syncChatIndex() {
    const selected = filteredChats.findIndex(chat => chat.id === beeperData.currentChatID);
    chatIndex = selected >= 0 ? selected : Math.max(0, Math.min(chatIndex, filteredChats.length - 1));
  }
  function ensureInitialChat() {
    if (!active || !beeperData.connected || beeperData.currentChatID || !filteredChats.length) return;
    chooseChat(0);
  }
  function openChatSearch() {
    closeConversationSearch(false); searchOpen = true; selectSearchChat(0);
    Qt.callLater(() => { if (active && searchOpen) searchField.forceActiveFocus(); });
  }
  function closeChatSearch() { searchOpen = false; searchChatID = ""; searchField.text = ""; if (active) navigationFocus.forceActiveFocus(); }
  function selectSearchChat(index) {
    if (!searchOpen) return;
    searchChatID = filteredChats[index]?.id || "";
    Qt.callLater(revealSearchChat);
  }
  function revealSearchChat() {
    if (!active || !searchOpen) return;
    const index = filteredChats.findIndex(chat => chat.id === searchChatID);
    if (index >= 0) sidebar.revealChat(index);
  }
  function cycleSearchChat(delta) {
    if (!searchOpen || !filteredChats.length) return;
    const index = filteredChats.findIndex(chat => chat.id === searchChatID);
    selectSearchChat((index + delta + filteredChats.length) % filteredChats.length);
  }
  function acceptChatSearch() {
    const index = filteredChats.findIndex(chat => chat.id === searchChatID);
    if (!searchOpen || index < 0) return;
    chooseChat(index); closeChatSearch(); navigation = "messages";
    sidebar.revealChat(chatIndex);
  }
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
    cancelReplyNavigation();
    cancelSearchNavigation(); messageSearch.close();
    if (restoreFocus && active) focusNavigation();
  }
  function acceptConversationSearch() {
    navigation = "messages"; navigationFocus.forceActiveFocus(); messageSearch.accept();
  }
  function revealSearchMatch(message) {
    if (!active || !messageSearch.opened || message.chatID !== beeperData.currentChatID) return;
    cancelReplyNavigation();
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
    pendingReadNavigation = null;
    gPending = false;
    beeperData.unreadFirst = !unreadFirst;
    syncChatIndex();
    // Reorder the sidebar without reopening the chat or touching its draft,
    // message selection or read state. Reveal the new start of the list.
    Qt.callLater(sidebar.revealFirstChat);
    schedulePagination();
  }
  function markSelectedChatRead() {
    const chat = beeperData.currentChat;
    if (!chat || beeperData.readStateOperations[chat.id]) return;
    const navigation = {id: chat.id, generation: beeperData.chatGeneration, network: networkFilter,
      lowPriority: showLowPriority, mode: root.navigation, previewID: chat.preview?.id || "",
      advance: unreadFirst && Format.isChatUnread(chat), held: false};
    pendingReadNavigation = navigation;
    const accepted = beeperData.markChatRead(chat.id, "", (result, error) => {
      // A successful reply may still contain the previous unread flags.
      // Keep the navigation intent until the shared store confirms "read".
      if ((error || !navigation.advance) && pendingReadNavigation === navigation) pendingReadNavigation = null;
    });
    if (!accepted && pendingReadNavigation === navigation) pendingReadNavigation = null;
  }
  function toggleLowPriorityView() {
    if (!active || !windowFocused || modal || recording || preparingRecording || messageSearch.opened) return;
    rememberPosition(); gPending = false;
    beeperData.showLowPriority = !showLowPriority;
    const index = filteredChats.findIndex(chat => chat.id === beeperData.currentChatID);
    if (index >= 0) { chatIndex = index; sidebar.revealChat(index); }
    else if (filteredChats.length) chooseChat(chatIndex);
    else { editMessageID = ""; messageIndex = -1; beeperData.clearSelection(); }
    focusNavigation(); schedulePagination();
  }
  function toggleSelectedPriority() {
    if (!active || !windowFocused || modal || recording || preparingRecording || messageSearch.opened || !beeperData.currentChat) return;
    rememberPosition();
    beeperData.setChatLowPriority(beeperData.currentChatID, !beeperData.currentChat.isLowPriority);
  }
  function reconcilePrioritySelection() {
    if (!active || !beeperData?.currentChat || Format.isChatInView(beeperData.currentChat, showLowPriority)) return;
    if (filteredChats.length) chooseChat(chatIndex);
    else { editMessageID = ""; messageIndex = -1; beeperData.clearSelection(); }
    focusNavigation();
  }
  function openChat(chatID, messageID) { closeConversationSearch(false); pinLatest = false; pendingOpenMessageID = messageID || ""; beeperData.selectChat(chatID, messageID || ""); navigation = "messages"; }
  function chooseChat(index, reveal = true) {
    if (!filteredChats.length) return;
    chatIndex = Math.max(0, Math.min(filteredChats.length - 1, index));
    rememberPosition();
    if (recording || preparingRecording) stopRecording();
    editMessageID = ""; beeperData.selectChat(filteredChats[chatIndex].id, "", true); messageIndex = -1;
    if (reveal) sidebar.revealChat(chatIndex);
  }
  function moveMessageSelection(delta) {
    cancelReplyNavigation();
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
    cancelReplyNavigation();
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
  function compose() { if (composerSurface.enabled && beeperData.currentChatID) { cancelReplyNavigation(); navigation = "compose"; composer.forceActiveFocus(); } }
  function navigatePane(right) {
    if (right && searchOpen) { acceptChatSearch(); return; }
    composerSurface.closeEmojiPicker();
    closeChatSearch(); closeConversationSearch(false); gPending = false;
    if (!right) focusNavigation();
    else if (composerSurface.enabled) compose();
    else if (beeperData.currentChatID) { navigation = "messages"; navigationFocus.forceActiveFocus(); }
  }
  function pickAttachment() {
    if (!canPickAttachment) return;
    const chatID = beeperData.currentChatID;
    const picker = attachmentPickerFactory.createObject(root);
    if (!picker) { beeperData.lastError = "Could not open the file picker."; return; }
    attachmentPickerStarted = false;
    attachmentPicker = picker;
    picker.finished.connect((paths, error) => {
      attachmentPicker = null;
      attachmentPickerStarted = false;
      if (error) beeperData.lastError = error;
      else if (paths.length) beeperData.stageAttachments(paths, chatID);
      nativeDialogClosed();
      if (active && beeperData.currentChatID === chatID) compose();
      picker.destroy();
    });
    nativeDialogOpened();
    startAttachmentPicker();
  }
  function startAttachmentPicker() {
    if (!attachmentPicker || attachmentPickerStarted || !attachmentPickerReady) return;
    attachmentPickerStarted = true;
    attachmentPicker.open();
  }
  function openModal(name) {
    if (name !== "help" && name !== "media" && name !== "attachments" && name !== "draw") return;
    modal = name;
    if ((photoPreviewOpen || imageEditorOpen) && externalPhotoPreview) return;
    Qt.callLater(() => modalSurface.forceActiveFocus());
  }
  function closeModal() { modal = ""; previewOrigin = null; navigationFocus.forceActiveFocus(); }
  function requestModalClose() {
    if (photoPreviewOpen && !externalPhotoPreview) dialogs.requestClose();
    else closeModal();
  }
  function openMedia(attachment, sourceItem = null) {
    previewOrigin = sourceItem;
    previewAttachment = attachment;
    locatePreview(sourceItem?.attachment || attachment);
    openModal("media");
  }
  function drawAttachment(index) {
    const attachment = beeperData.draftAttachments[index];
    if (!active || modal || recording || preparingRecording || beeperData.sending || beeperData.stagingAttachments
        || !attachment || Format.attachmentType(attachment) !== "image" || attachment.isSticker) return;
    imageEditChatID = beeperData.currentChatID; imageEditIndex = index; imageEditOriginal = attachment;
    previewAttachment = attachment; previewOrigin = null;
    composerSurface.closeEmojiPicker(); openModal("draw");
  }
  function completeImageEdit(attachment) {
    const replaced = beeperData.replaceDraftImage(imageEditChatID, imageEditIndex, imageEditOriginal, attachment);
    closeModal(); compose();
    if (!replaced) beeperData.lastError = "This image is no longer in the draft.";
  }
  function openSelectedAttachments() {
    const attachments = selectedMessage?.attachments || [];
    if (!attachments.length) return;
    if (attachments.length === 1) { openSelectedAttachment(0); return; }
    attachmentChoiceMessageID = selectedMessage.id;
    attachmentChoices = attachments.map((attachment, index) => ({
      index: index, attachment: attachment,
      title: attachment.fileName || ({image: "Photo", gif: "GIF", video: "Video", audio: "Audio", file: "File"})[Format.attachmentType(attachment)],
      detail: [attachment.mimeType || attachment.mime || "", Format.bytes(attachment.fileSize)].filter(Boolean).join(" · ")
    }));
    openModal("attachments");
  }
  function openSelectedAttachment(index) {
    const message = selectedMessage, attachment = message?.attachments?.[index], chatID = beeperData.currentChatID;
    if (!attachment) return;
    if (Format.attachmentType(attachment) === "audio") {
      beeperData.audioPlayback.play(JSON.stringify([message.chatID || chatID, message.id, index]), attachment);
      return;
    }
    messageList.positionViewAtIndex(messageIndex, ListView.Contain);
    Qt.callLater(() => {
      if (!active || !windowFocused || modal || composer.activeFocus || beeperData.currentChatID !== chatID
          || selectedMessage?.id !== message.id || !selectedMessage.attachments?.[index]
          || Format.attachmentSource(selectedMessage.attachments[index]) !== Format.attachmentSource(attachment)) return;
      const media = messageList.itemAtIndex(messageIndex)?.attachmentItem(index) || null;
      if (Format.attachmentType(attachment) === "file") { media?.openFile(); return; }
      openMedia(media?.sourceReady ? Object.assign({}, attachment, {srcURL: media.sourceUrl}) : attachment, media);
    });
  }
  // Preview copies may carry a downloaded srcURL; the history keeps the original.
  function locatePreview(attachment) {
    previewMessageID = ""; previewAttachmentIndex = -1;
    for (let i = beeperData.messages.length - 1; i >= 0; --i) {
      const index = (beeperData.messages[i].attachments || []).findIndex(item =>
        item === attachment || !!attachment?.id && item.id === attachment.id);
      if (index >= 0) { previewMessageID = beeperData.messages[i].id; previewAttachmentIndex = index; return; }
    }
  }
  // h / l in the photo viewer walk this chat's photos and GIFs, oldest first.
  // Videos keep h / l for seeking. The message selection follows, so closing
  // returns to the photo shown last; older pages load when h reaches the top.
  function stepPreview(delta) {
    if (!photoPreviewOpen || videoPreviewOpen || !previewMessageID) return;
    const images = [];
    beeperData.messages.forEach((message, messageIndex) => (message.attachments || []).forEach((attachment, attachmentIndex) => {
      if (["image", "gif"].includes(Format.attachmentType(attachment)))
        images.push({message: message, messageIndex: messageIndex, attachment: attachment, attachmentIndex: attachmentIndex});
    }));
    const current = images.findIndex(image => image.message.id === previewMessageID && image.attachmentIndex === previewAttachmentIndex);
    const image = current >= 0 ? images[current + delta] : null;
    if (!image) {
      if (current >= 0 && delta < 0 && beeperData.hasOlderMessages) {
        if (!pendingPreviewStep) previewPagesLeft = 10;
        if (previewPagesLeft-- > 0) { pendingPreviewStep = delta; beeperData.loadMessages(true); return; }
      }
      pendingPreviewStep = 0;
      return;
    }
    pendingPreviewStep = 0;
    previewMessageID = image.message.id; previewAttachmentIndex = image.attachmentIndex;
    messageIndex = image.messageIndex;
    messageList.positionViewAtIndex(image.messageIndex, ListView.Contain);
    const media = messageList.itemAtIndex(image.messageIndex)?.attachmentItem(image.attachmentIndex) || null;
    previewOrigin = media;
    previewAttachment = media?.sourceReady ? Object.assign({}, image.attachment, {srcURL: media.sourceUrl}) : image.attachment;
  }
  function resumePreviewStep() { if (pendingPreviewStep) stepPreview(pendingPreviewStep); }
  function submitMessage() {
    if (recorder || preparingRecording || composer.inputMethodComposing) return;
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
  function toggleSelectedAudio() {
    const message = selectedMessage, attachments = message?.attachments || [], audio = beeperData.audioPlayback;
    const key = index => JSON.stringify([message.chatID || beeperData.currentChatID, message.id, index]);
    // If this message holds several voices, keep controlling the one opened with o.
    let index = attachments.findIndex((attachment, i) => Format.attachmentType(attachment) === "audio" && audio.key === key(i));
    if (index < 0) index = attachments.findIndex(attachment => Format.attachmentType(attachment) === "audio");
    if (index >= 0) audio.toggle(key(index), attachments[index]);
  }
  function claimTextSelection(owner) {
    if (textSelectionOwner && textSelectionOwner !== owner) textSelectionOwner.clearTextSelection();
    textSelectionOwner = owner;
  }
  function clearTextSelection() { textSelectionOwner?.clearTextSelection(); textSelectionOwner = null; }
  function copyText(text, confirmation) {
    clipboardWriter(text);
    notice = confirmation; noticeTimer.restart();
  }
  // l: the first link of the selected message, in the default browser.
  function openSelectedLink() {
    const links = Format.messageLinks(selectedMessage);
    notice = !links.length ? "This message has no link"
      : linkOpener(links[0].url) === false ? "Could not open this link"
      : links.length > 1 ? "Opened the first of " + links.length + " links" : "Link opened";
    noticeTimer.restart();
  }
  // y: the text selected with the mouse, else the whole selected message.
  function yank() {
    if (selectedText) { copyText(selectedText, "Selection copied"); clearTextSelection(); return; }
    const text = Format.text(selectedMessage);
    if (text) copyText(text, "Message copied");
    else { notice = "This message has no text"; noticeTimer.restart(); }
  }
  function saveSelectedAttachments() {
    if (beeperData.saveMessageAttachments(selectedMessage)) {
      notice = "Saving attachments…"; noticeTimer.restart();
    }
  }
  function cancelReplyNavigation() {
    if (!replyTargetID) return;
    if (replyTargetID && pendingOpenMessageID === replyTargetID) pendingOpenMessageID = "";
    replyTargetID = ""; targetPageCount = 0;
    if (notice === "Loading original message…") notice = "";
  }
  function jumpToOriginal() {
    const target = selectedMessage?.linkedMessageID;
    if (!target || replyTargetID === target) return;
    closeConversationSearch(false);
    pendingOpenMessageID = ""; beeperData.targetMessageID = "";
    messageWheel.reset(); messageList.cancelFlick(); pinLatest = false; restoringView = false;
    navigation = "messages"; navigationFocus.forceActiveFocus();
    replyTargetID = target;
    notice = "Loading original message…"; noticeTimer.stop();
    resumeReplyNavigation();
  }
  function resumeReplyNavigation() {
    if (!replyTargetID || !active) return;
    const original = beeperData.quote(replyTargetID);
    if (original.state === "idle") { beeperData.ensureQuote(replyTargetID); return; }
    if (original.state === "loading") return;
    if (original.state !== "ready") {
      cancelReplyNavigation(); notice = "Original message unavailable"; noticeTimer.restart(); return;
    }
    if (pendingOpenMessageID === replyTargetID) return;
    pendingOpenMessageID = replyTargetID; targetPageCount = 0;
    beeperData.messagesPaginationBlocked = false;
    historyUpdatePending = true;
    finishHistoryUpdate();
  }
  function startRecording() {
    if (!canStartRecording) return;
    if (beeperData.demo) { beeperData.lastError = "The design preview does not activate the microphone."; return; }
    const generation = ++recordingGeneration;
    preparingRecording = true; recordingCancelled = false; recordingChatID = beeperData.currentChatID;
    beeperData.request("prepareRecording", {}, (result, error) => {
      if (generation !== recordingGeneration) {
        if (result?.path) beeperData.request("discardAttachment", {path: result.path});
        return;
      }
      preparingRecording = false;
      if (error || !result?.path) return;
      if (!canStartRecording || recordingChatID !== beeperData.currentChatID) { beeperData.request("discardAttachment", {path: result.path}); return; }
      recordingAttachment = result;
      recorder = recorderFactory.createObject(root, {outputPath: result.path});
      if (!recorder) {
        beeperData.lastError = "Could not start the voice recorder.";
        recordingAttachment = null; beeperData.request("discardAttachment", {path: result.path}); return;
      }
      recorder.start();
    });
  }
  function stopRecording() {
    if (preparingRecording) { ++recordingGeneration; preparingRecording = false; }
    if (recorder) recorder.stop();
  }
  function cancelRecording() {
    recordingCancelled = true;
    stopRecording();
  }
  function toggleRecording() {
    if (recording || preparingRecording) stopRecording();
    else if (canStartRecording) { composerSurface.closeEmojiPicker(); startRecording(); }
  }
  function userHistoryScroll() {
    cancelReplyNavigation();
    cancelSearchNavigation();
    pinLatest = false; restoringView = false; historyWheelTimer.restart();
    Qt.callLater(rememberPosition);
  }
  function toggleShelbyCollapsed() {
    if (!beeperData.toggleShelbyCollapsed()) return;
    notice = beeperData.shelbyCollapsed ? "Shelby: 3 lines" : "Shelby: full messages"; noticeTimer.restart();
    // Heights change under the viewport; keep the selected message in view.
    if (selectedMessage) Qt.callLater(() => { if (messageIndex >= 0) messageList.positionViewAtIndex(messageIndex, ListView.Contain); });
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
    if ((!active && beeperData.viewOwner !== root) || !displayedChatID || !messageList.count || messageList.loading || restoringView) return;
    const index = Math.max(0, messageList.indexAt(1, messageList.contentY + 12)), item = messageList.itemAtIndex(index);
    beeperData.viewPositions[displayedChatID] = {atLatest: pinLatest || messageList.atYEnd, messageID: beeperData.messages[index]?.id || "", offset: item ? messageList.contentY - item.y : 0, contentY: messageList.contentY};
  }
  function captureArrivals() {
    const messages = beeperData.messages;
    arrivalBaseline = active && visible && !!beeperData.currentChatID
      && (messages.length || arrivalReadyChatID === beeperData.currentChatID)
      && displayedChatID === beeperData.currentChatID
      && (pinLatest || (!historyInteracting && messageList.atYEnd))
      ? {chatID: beeperData.currentChatID, tail: messages.length ? messages[messages.length - 1].id : null,
          ids: new Set(messages.map(message => message.id))} : null;
  }
  function collectArrivals(older) {
    const before = arrivalBaseline;
    arrivalBaseline = null;
    if (older || !active || !before || before.chatID !== beeperData.currentChatID) return;
    const tail = before.tail === null ? -1 : beeperData.messages.findIndex(message => message.id === before.tail);
    if (before.tail !== null && tail < 0) return;
    const added = beeperData.messages.slice(tail + 1).filter(message => !before.ids.has(message.id));
    if (added.length) messageList.queueArrivals(added.map(message => message.id));
  }
  function restorePosition() {
    if (!active) return;
    if (historyInteracting && !pinLatest && displayedChatID === beeperData.currentChatID) {
      restoringView = false; updateView(); return;
    }
    restoringView = true;
    if (messageList.loading) return;
    if ((beeperData.loadingMessages || beeperData.historyLoadPending) && !beeperData.messages.length) return;
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
    } else {
      // Keep the end anchor through delayed bubble and viewport resizing.
      // Wheel, scrollbar and message navigation release it explicitly.
      pinLatest = true;
      messageList.positionViewAtEnd();
    }
    displayedChatID = beeperData.currentChatID;
    Qt.callLater(() => { restoringView = false; updateView(); schedulePagination(); });
  }
  function updateView() {
    if (!beeperData || !messageList) return;
    if (active) {
      beeperData.viewOwner = root;
      beeperData.viewFocused = !restoringView && windowFocused && modal !== "media" && modal !== "draw" && !connectionSurface.visible;
      beeperData.viewAtLatest = !restoringView && messageList.atYEnd;
    } else if (beeperData.viewOwner === root) { beeperData.viewOwner = null; beeperData.viewFocused = false; }
  }
  onActiveChanged: {
    if (!active) { pendingReadNavigation = null; arrivalBaseline = null; messageList.clearArrivals(); }
    if (!active) { rememberPosition(); clearMessageSelection(); closeConversationSearch(false); messageWheel.reset(); messageList.cancelFlick(); historyWheelTimer.stop(); pinLatest = false; stopRecording(); beeperData.flushDraft(); modal = ""; closeChatSearch(); }
    else { reconcilePrioritySelection(); restoringView = true; Qt.callLater(ensureInitialChat); Qt.callLater(restorePosition); }
    updateView(); schedulePagination();
  }
  onWindowFocusedChanged: {
    if (!windowFocused && !modal && !emojiPickerOpen) clearMessageSelection();
    updateView();
  }
  onModalChanged: { if (modal !== "attachments") { attachmentChoices = []; attachmentChoiceMessageID = ""; } if (modal !== "media") pendingPreviewStep = 0; updateView(); }
  onFilteredChatsChanged: {
    syncChatIndex();
    if (searchOpen && !filteredChats.some(chat => chat.id === searchChatID)) selectSearchChat(0);
    schedulePagination(); Qt.callLater(reconcilePrioritySelection); Qt.callLater(ensureInitialChat);
  }
  Connections {
    target: root.composer
    function onActiveFocusChanged() {
      if (root.composer.activeFocus) { root.clearMessageSelection(); root.navigation = "compose"; }
    }
  }
  Connections {
    target: root.beeperData
    function onReadStateApplying(chatID) {
      const navigation = root.pendingReadNavigation;
      if (!navigation || navigation.id !== chatID || !navigation.advance) return;
      // An asynchronous completion is not a keyboard shortcut: a temporary
      // loss of native focus must not make the selection follow the read row.
      // Actual navigation, typing, a changed view or new activity cancels it.
      if (!root.active || !root.unreadFirst || root.modal || root.searchOpen || messageSearch.opened
          || root.recording || root.preparingRecording || root.composer.activeFocus
          || root.navigation !== navigation.mode || root.beeperData.currentChatID !== chatID
          || root.beeperData.chatGeneration !== navigation.generation
          || root.networkFilter !== navigation.network || root.showLowPriority !== navigation.lowPriority
          || (root.beeperData.currentChat?.preview?.id || "") !== navigation.previewID) {
        root.pendingReadNavigation = null;
        return;
      }
      navigation.index = root.chatIndex;
      navigation.viewport = sidebar.holdReadViewport();
      navigation.held = true;
    }
    function onReadStateApplied(chatID) {
      const navigation = root.pendingReadNavigation;
      if (!navigation || navigation.id !== chatID || !navigation.held) return;
      root.pendingReadNavigation = null;
      const unread = root.filteredChats.filter(Format.isChatUnread);
      const next = unread[Math.min(navigation.index, unread.length - 1)];
      root.chooseChat(next ? root.filteredChats.findIndex(item => item.id === next.id) : 0, false);
      root.navigation = "chats";
      if (root.windowFocused) root.focusNavigation();
      sidebar.releaseReadViewport(navigation.viewport, root.chatIndex);
    }
    function onAttachmentsSaved(chatID, messageID, saved, total, directory) {
      if (!root.active || root.beeperData.currentChatID !== chatID) return;
      root.notice = saved === total ? "Saved " + saved + (saved === 1 ? " attachment to " : " attachments to ") + directory
        : "Saved " + saved + " / " + total + " attachments · " + (total - saved) + " failed";
      noticeTimer.restart();
    }
    function onChatPriorityChanged(chatID, lowPriority) {
      if (root.beeperData.currentChatID === chatID) root.reconcilePrioritySelection();
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
      messageList.invalidateLayout();
      if (root.restoringView) Qt.callLater(root.restorePosition);
      else messageWheel.shiftOrigin(messageList.takeAnchorShift());
      Qt.callLater(root.resumeReplyNavigation);
    }
    function onLoadingChanged() { root.schedulePagination(); }
    function onLoadingMessagesChanged() {
      root.schedulePagination();
      if (root.replyTargetID && !root.beeperData.loadingMessages && root.beeperData.messagesPaginationBlocked) {
        root.cancelReplyNavigation(); root.notice = "Could not load the original message. Press i to retry."; noticeTimer.restart();
      }
      if (root.locatingSearchResult && !root.beeperData.loadingMessages && root.beeperData.messagesPaginationBlocked) {
        root.cancelSearchNavigation();
        messageSearch.errorText = "Could not load the matching message. Press Enter to retry.";
      }
    }
    function onConnectedChanged() { root.schedulePagination(); Qt.callLater(root.ensureInitialChat); }
    function onMessagesUpdating() {
      if (!root.active) return;
      root.captureArrivals();
      root.selectedMessageIDBeforeUpdate = root.selectedMessage?.id || "";
      if (root.historyInteracting) messageList.captureMovingAnchor();
      else { root.rememberPosition(); root.restoringView = true; }
    }
    function onCurrentChatIDChanged() {
      root.arrivalBaseline = null; messageList.clearArrivals();
      root.arrivalReadyChatID = "";
      root.historyUpdatePending = false;
      root.pendingPreviewStep = 0;
      if (root.preparingRecording) root.stopRecording();
      if (root.modal === "attachments" || root.imageEditorOpen) root.closeModal();
      root.closeConversationSearch(false);
      root.messageIndex = -1; root.selectedMessageIDBeforeUpdate = "";
      root.syncChatIndex();
      Qt.callLater(root.ensureInitialChat);
      if (root.active) { root.rememberPosition(); root.restoringView = true; }
      messageWheel.reset(); messageList.cancelFlick(); historyWheelTimer.stop(); root.pinLatest = false;
    }
    function onMessagesLoaded(older) {
      root.collectArrivals(older);
      // An empty successful history is a baseline too. Record it only after
      // collecting, so opening a conversation never animates its first page.
      root.arrivalReadyChatID = root.beeperData.currentChatID;
      root.historyUpdatePending = true;
      root.finishHistoryUpdate();
      if (older && root.pendingPreviewStep) Qt.callLater(root.resumePreviewStep);
    }
  }
  function finishHistoryUpdate() {
    if (!root.active || messageList.loading) return;
    root.historyUpdatePending = false;
    if (root.selectedMessageIDBeforeUpdate) {
      root.messageIndex = root.beeperData.messages.findIndex(message => message.id === root.selectedMessageIDBeforeUpdate);
      root.selectedMessageIDBeforeUpdate = "";
    }
    const wanted = root.pendingOpenMessageID || root.beeperData.targetMessageID || "";
    if (wanted) root.pinLatest = false;
    const index = wanted ? root.beeperData.messages.findIndex(message => message.id === wanted) : -1;
    if (index >= 0) { root.messageIndex = index; messageList.positionViewAtIndex(index, ListView.Center); root.cancelReplyNavigation(); root.pendingOpenMessageID = ""; root.beeperData.targetMessageID = ""; root.targetPageCount = 0; root.locatingSearchResult = false; root.restoringView = false; }
    else if (wanted && root.beeperData.hasOlderMessages && !root.beeperData.messagesPaginationBlocked
        && (root.locatingSearchResult || root.replyTargetID || root.targetPageCount < 20)) {
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
      else if (root.replyTargetID) { root.cancelReplyNavigation(); root.notice = "Original message unavailable in this conversation"; noticeTimer.restart(); }
      else root.beeperData.lastError = "This message is not available in the loaded history.";
      root.pendingOpenMessageID = ""; root.beeperData.targetMessageID = ""; root.targetPageCount = 0;
      root.locatingSearchResult = false; root.restoringView = false;
    }
    else if (root.restoringView || root.pinLatest || root.displayedChatID !== root.beeperData.currentChatID) root.restorePosition();
    else messageWheel.shiftOrigin(messageList.takeAnchorShift());
    root.displayedChatID = root.beeperData.currentChatID;
    root.updateView();
    root.schedulePagination();
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
    BeeperRecorder {}
  }
  Component {
    id: attachmentPickerComponent
    BeeperAttachmentPicker {}
  }
  Connections {
    target: root.recorder
    function onFinished(path) {
      const finishedRecorder = root.recorder;
      if (root.recordingCancelled) root.beeperData.request("discardAttachment", {path: path});
      else if (root.recordingChatID === root.beeperData.currentChatID) root.beeperData.draftAttachments = [root.recordingAttachment];
      else root.beeperData.request("saveDraft", {chatID: root.recordingChatID, text: root.beeperData.localDrafts[root.recordingChatID]?.text || "", attachment: root.recordingAttachment});
      root.recorder = null; root.recordingAttachment = null;
      finishedRecorder.destroy();
    }
    function onFailed(message) {
      const failedRecorder = root.recorder;
      if (root.recordingCancelled) root.beeperData.request("discardAttachment", {path: root.recordingAttachment.path});
      else root.beeperData.lastError = message;
      root.recorder = null; root.recordingAttachment = null;
      failedRecorder.destroy();
    }
  }
  Item { id: navigationFocus; focus: true }
  // Register from a window-backed item so Escape also works in the composer,
  // popups and the separate fullscreen window. Only the active monitor owns it.
  Shortcut {
    sequence: "Escape"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.active && (root.windowFocused && (root.recorder !== null || root.preparingRecording) || !!root.beeperData.audioPlayback?.active)
    onActivated: {
      if (root.recorder || root.preparingRecording) root.cancelRecording();
      else root.beeperData.audioPlayback.pause();
    }
  }
  Shortcut {
    sequence: "Space"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.canUseMessageShortcuts && !!root.selectedMessage
    onActivated: root.toggleSelectedAudio()
  }
  Shortcut {
    sequence: "O"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.canUseMessageShortcuts && !!root.selectedMessage?.attachments?.length
    onActivated: root.openSelectedAttachments()
  }
  Shortcut {
    sequence: "I"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.canUseMessageShortcuts && !!root.selectedMessage?.linkedMessageID
    onActivated: root.jumpToOriginal()
  }
  Shortcut {
    sequence: "D"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.canUseMessageShortcuts && !!root.selectedMessage?.attachments?.length
    onActivated: root.saveSelectedAttachments()
  }
  Shortcut {
    sequence: "H"; context: Qt.WindowShortcut
    enabled: root.canSeekAudio
    onActivated: root.beeperData.audioPlayback.seek(-5000)
  }
  Shortcut {
    sequence: "L"; context: Qt.WindowShortcut
    enabled: root.canSeekAudio
    onActivated: root.beeperData.audioPlayback.seek(5000)
  }
  Shortcut {
    sequence: "Ctrl+H"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canNavigatePanes
    onActivated: root.navigatePane(false)
  }
  Shortcut {
    sequence: "Ctrl+L"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canNavigatePanes
    onActivated: root.navigatePane(true)
  }
  Shortcut {
    sequence: "Ctrl+F"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.canPickAttachment
    onActivated: root.pickAttachment()
  }
  Shortcut {
    sequence: "Ctrl+S"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.canUseComposerShortcuts && composerSurface.canPickEmoji
    onActivated: composerSurface.toggleEmojiPicker()
  }
  Shortcut {
    sequence: "Ctrl+D"; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.active && root.windowFocused && !root.composer.inputMethodComposing
      && (root.recording || root.preparingRecording || root.canUseComposerShortcuts && root.canStartRecording)
    onActivated: root.toggleRecording()
  }
  Shortcut {
    sequences: ["Return", "Enter"]; context: Qt.ApplicationShortcut; autoRepeat: false
    enabled: root.active && root.windowFocused && !root.composer.inputMethodComposing
      && (root.recording || root.preparingRecording)
    onActivated: { root.stopRecording(); if (!root.modal) root.compose(); }
  }
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
    enabled: root.canNavigateSearchChats || root.canNavigateMessages
    onActivated: root.searchOpen ? root.cycleSearchChat(1)
      : messageSearch.opened ? messageSearch.move(1) : root.moveMessageSelection(1)
  }
  Shortcut {
    sequence: "Ctrl+K"; context: Qt.WindowShortcut
    enabled: root.canNavigateSearchChats || root.canNavigateMessages
    onActivated: root.searchOpen ? root.cycleSearchChat(-1)
      : messageSearch.opened ? messageSearch.move(-1) : root.moveMessageSelection(-1)
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
      if (modal) requestModalClose();
      else if (replyTargetID) cancelReplyNavigation();
      else if (selectedText) clearTextSelection();
      else if (messageSearch.opened) closeConversationSearch();
      else if (searchOpen) { closeChatSearch(); navigation = "chats"; }
      else if (beeperData.replyToMessageID || editMessageID) { beeperData.replyToMessageID = ""; editMessageID = ""; }
      else if (beeperData.draftAttachment) beeperData.clearAttachment();
      else if (composer.activeFocus || navigation === "messages" || navigation === "compose") focusNavigation();
      else if (showLowPriority) toggleLowPriorityView();
      else closeRequested();
      event.accepted = true; return;
    }
    if (connectionSurface.visible || modal || composer.activeFocus || searchField.activeFocus || tokenField.activeFocus || conversationSearchBar.input.activeFocus) return;
    const key = event.text || (event.key >= Qt.Key_A && event.key <= Qt.Key_Z ? String.fromCharCode(event.key + (event.modifiers & Qt.ShiftModifier ? 0 : 32)) : "");
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U) {
      messageWheel.reset();
      pinLatest = false;
      const list = navigation === "chats" ? chatList : messageList;
      list.flickTo(Qt.point(list.contentX, Math.max(list.originY, Math.min(list.originY + list.contentHeight - list.height, list.contentY - list.height * 0.5)))); event.accepted = true;
    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && selectedText) {
      copyText(selectedText, "Selection copied"); event.accepted = true;
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
        if (key === "A" || (event.modifiers & Qt.ShiftModifier)) toggleSelectedPriority();
        else toggleLowPriorityView();
      }
      event.accepted = true;
    }
    else if (key === "j" || key === "k") { chooseChat(chatIndex + (key === "j" ? 1 : -1)); focusNavigation(); event.accepted = true; }
    else if (key === "h") { focusNavigation(); event.accepted = true; }
    else if (key === "g") { if (gPending) { goEdge(false); gPending = false; } else { gPending = true; gTimer.restart(); } event.accepted = true; }
    else if (key === "G") { goEdge(true); event.accepted = true; }
    else if (key === "/") { openChatSearch(); event.accepted = true; }
    else if (key === "?" || event.key === Qt.Key_Question) { if (!event.isAutoRepeat) openModal("help"); event.accepted = true; }
    else if (key === "q" && beeperData.canCollapseShelby) { if (!event.isAutoRepeat) toggleShelbyCollapsed(); event.accepted = true; }
    else if (key === "m" && beeperData.currentChatID) { if (!event.isAutoRepeat) markSelectedChatRead(); event.accepted = true; }
    else if (key === "n" && beeperData.currentChatID) {
      if (!event.isAutoRepeat) { pendingReadNavigation = null; beeperData.markChatUnread(beeperData.currentChatID); }
      event.accepted = true;
    }
    else if (key === "r" && selectedMessage) { replyToSelectedMessage(); event.accepted = true; }
    else if (key === "e" && selectedMessage?.isSender) { editSelectedMessage(); event.accepted = true; }
    // While audio plays, the l Shortcut seeks first and this key never arrives.
    else if (key === "l" && selectedMessage) { if (!event.isAutoRepeat) openSelectedLink(); event.accepted = true; }
    else if (key === "y" && (selectedText || selectedMessage)) { if (!event.isAutoRepeat) yank(); event.accepted = true; }
    else if (/^[1-6]$/.test(key) && selectedMessage) { if (!event.isAutoRepeat) reactToSelectedMessage(quickReactions[Number(key) - 1]); event.accepted = true; }
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
      readStateOperations: root.beeperData.readStateOperations
      chatPreviews: root.beeperData.chatPreviews || ({})
      currentNetwork: root.currentNetwork
      showLowPriority: root.showLowPriority
      unreadFirst: root.unreadFirst
      accountConnectionIssues: root.beeperData.accountConnectionIssues
      serviceConnectionIssue: root.beeperData.serviceConnectionIssue
      currentChatID: root.searchOpen ? root.searchChatID : root.beeperData.currentChatID
      unreadCount: root.beeperData.unreadConversationCount(root.networkFilter)
      unreadReady: root.beeperData.unreadCountsReady
      unreadLoading: root.beeperData.loadingUnreadCounts
      searchOpen: root.searchOpen
      onNetworkCycleRequested: root.cycleNetwork(1)
      onSearchChanged: root.selectSearchChat(0)
      onSearchCycled: delta => root.cycleSearchChat(delta)
      onSearchAccepted: root.acceptChatSearch()
      onChatSelected: index => {
        if (root.searchOpen) { root.selectSearchChat(index); root.acceptChatSearch(); }
        else { root.chooseChat(index); root.navigation = "chats"; navigationFocus.forceActiveFocus(); }
      }
      onViewportChanged: root.schedulePagination()
    }

    ColumnLayout {
      id: conversationColumn
      objectName: "beeperConversationColumn"
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: root.compact ? 14 : 25
      spacing: 0
      BeeperSearchBar {
        id: conversationSearchBar
        Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.bottomMargin: 10
        controller: messageSearch
        accent: root.conversationAccent
        locating: root.locatingSearchResult
        onAcceptRequested: root.acceptConversationSearch()
        onCloseRequested: root.closeConversationSearch()
      }
      Item {
        Layout.fillWidth: true; Layout.fillHeight: true
        enabled: !connectionSurface.visible
        BeeperHistory {
          id: messageList; objectName: "beeperMessages"
          textScale: root.beeperData.chatTextSize / Theme.beeperFont.body
          shiftViewport: delta => messageWheel.shiftOrigin(delta)
          anchors { fill: parent; bottomMargin: 12 }
          clip: true
          // Keep the closing morph intact, but do not build histories for
          // panels on other monitors or after this panel becomes invisible.
          model: KeyedListModel { rows: root.visible ? root.beeperData.messages : []; immutableRows: true }
          onLayoutReady: {
            if (root.historyUpdatePending) root.finishHistoryUpdate();
            else if (root.active && root.restoringView) root.restorePosition();
          }
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
            id: messageDelegate
            required property var row
            required property int index
            width: messageList.width
            message: row; beeperData: root.beeperData
            networkAccent: root.conversationAccent
            searchQuery: messageSearch.opened ? messageSearch.query : ""
            // Message search must be able to show matches past the third line.
            collapsed: root.beeperData.collapseShelby && !messageSearch.opened
            selected: index === root.messageIndex
            playbackEnabled: root.active && !root.videoPreviewOpen
            viewportReady: false
            inViewport: false
            inVisibleViewport: false
            renderMedia: viewportReady && root.visible && inViewport
            onSelectedRequested: { root.cancelReplyNavigation(); root.messageIndex = index; root.navigation = "messages"; navigationFocus.forceActiveFocus(); }
            onPreviewRequested: (attachment, sourceItem) => root.openMedia(attachment, sourceItem)
            onTextSelectionStarted: root.claimTextSelection(messageDelegate)
            onCopyLinkRequested: url => root.copyText(url, "Link copied")
          }
        }
        Rectangle {
          objectName: "beeperNotice"
          anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 24 }
          width: noticeLabel.implicitWidth + 36; height: 36; radius: 18
          color: Theme.surfaceRaised
          visible: root.notice !== ""
          Text {
            id: noticeLabel
            objectName: "beeperNoticeText"
            anchors.centerIn: parent
            text: root.notice
            color: Theme.foreground
            font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
          }
        }
        Timer { id: noticeTimer; interval: 1600; onTriggered: root.notice = "" }
        Column {
          visible: !connectionSurface.visible && (!root.beeperData.currentChatID || (root.beeperData.messages.length === 0 && !root.beeperData.loadingMessages && !root.beeperData.historyLoadPending))
          anchors.centerIn: parent; width: Math.min(parent.width - 40, 340); spacing: 15
          Icon {
            size: Theme.beeperFont.illustration; anchors.horizontalCenter: parent.horizontalCenter; name: "messages-square"; color: Qt.alpha(Theme.sideApplications, 0.6);  }
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
        BeeperButton { id: dismissError; anchors { right: parent.right; verticalCenter: parent.verticalCenter } iconName: "x"; Accessible.name: "Dismiss error"; onClicked: root.beeperData.lastError = "" }
      }
      RowLayout {
        objectName: "beeperSavedSendDraft"
        Layout.fillWidth: true; Layout.bottomMargin: 6; spacing: 8
        visible: root.beeperData.recoverableDrafts.length > 0 && !root.beeperData.sending && !connectionSurface.visible
        Text {
          Layout.fillWidth: true
          text: "Saved draft (" + root.beeperData.recoverableDrafts.length + ") · Check the conversation before resending."
          textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.secondary
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
        }
        BeeperButton {
          objectName: "beeperRestoreSendDraft"
          text: "Restore"; accent: root.conversationAccent
          enabled: root.active && !root.modal && !root.editMessageID && !root.recording && !root.preparingRecording && !root.beeperData.currentChat?.isReadOnly
          ToolTip.visible: hovered
          ToolTip.text: "Restore a saved draft. Your current draft is kept separately. Nothing is sent automatically."
          onClicked: { root.beeperData.restoreSavedSendDraft(); root.compose(); }
        }
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
        vimEditing: root.vimEditing
        onCopyRequested: text => root.copyText(text, "Text copied")
        onEditTextEdited: text => root.editText = text
        onDraftTextEdited: text => root.beeperData.draftText = text
        onSubmitRequested: root.submitMessage()
        onPasteAttachmentRequested: root.beeperData.pasteAttachment()
        onRecordingToggleRequested: root.toggleRecording()
        onAttachmentsDropped: urls => root.beeperData.stageAttachments(urls)
        onDrawAttachmentRequested: index => root.drawAttachment(index)
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
    previewOrigin: root.previewOrigin
    attachmentChoices: root.attachmentChoices
    vimEditing: root.vimEditing
    accent: root.conversationAccent
    onAttachmentSelected: index => {
      const choice = root.attachmentChoices[index];
      const attachment = root.selectedMessage?.attachments?.[index];
      if (root.selectedMessage?.id !== root.attachmentChoiceMessageID || !choice
          || !attachment || Format.attachmentSource(attachment) !== Format.attachmentSource(choice.attachment)) {
        root.closeModal(); root.notice = "Attachment no longer available"; noticeTimer.restart(); return;
      }
      root.closeModal(); root.openSelectedAttachment(index);
    }
    onDownloadRequested: root.saveSelectedAttachments()
    externalPhotoPreview: root.externalPhotoPreview
    onCloseRequested: { const editing = root.imageEditorOpen; root.closeModal(); if (editing) root.compose(); }
    onImageEdited: attachment => root.completeImageEdit(attachment)
    onPreviewStepRequested: delta => root.stepPreview(delta)
  }
}
