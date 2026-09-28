import QtQuick
import Quickshell
import Quickshell.Io
import "./BeeperFormat.js" as Format
import "../../ui/Theme.js" as Theme

// One instance is shared by all monitors. No credentials enter logs or Nix.
Scope {
  id: root
  property list<string> command: ["quickshell-beeper", "--stdio"]
  property bool enabled: true
  property bool demo: false
  property string state: demo ? "demo" : "loading-token"
  property real statusRevision: -1
  property bool savingToken: false
  readonly property string connectionState: state
  readonly property bool tokenRequired: state === "needs-token" || state === "invalid-token"
  property string statusMessage: ""
  property string lastError: ""
  readonly property bool connected: state === "connected" || state === "demo"
  property var accounts: []
  property bool loadingAccounts: false
  property int accountsGeneration: 0
  readonly property var accountConnectionIssues: Format.accountConnectionIssues(accounts, chats)
  readonly property string serviceConnectionIssue: Format.serviceConnectionIssue(state)
  property string networkFilter: "all"
  property bool showLowPriority: false
  property bool unreadFirst: false
  property var lowPriorityPending: ({})
  property int chatsRevision: 0
  property var reactionOperations: ({})
  property var chats: []
  property var unreadCounts: ({})
  property var lowPriorityUnreadCounts: ({})
  property bool lowPriorityUnreadCountsLoaded: false
  property bool unreadCountsLoaded: false
  property bool loadingUnreadCounts: false
  property bool unreadCountsDirty: false
  property bool unreadCountsUrgent: false
  property int unreadCountsGeneration: 0
  property real lastUnreadCountsAttempt: 0
  readonly property bool unreadCountsReady: demo || (unreadCountsLoaded && (!showLowPriority || lowPriorityUnreadCountsLoaded))
  property var messages: []
  readonly property var readReceiptReaders: Format.readReceiptReaders(messages, currentChat, accounts)
  property var quotedMessages: ({})
  property var waveforms: ({})
  readonly property alias audioPlayback: audioPlayback
  property var waveformQueue: []
  property bool waveformBusy: false
  property var searchResults: []
  property string currentChatID: ""
  property string targetMessageID: ""
  readonly property var currentChat: chats.find(chat => chat.id === currentChatID) || null
  property var senderColorRegistry: ({})
  property var senderColors: ({})
  property bool loading: false
  property bool loadingMessages: false
  property int navigationLoadDelay: 90
  readonly property bool historyLoadPending: navigationLoadTimer.running
  property bool trailingChatsRefresh: false
  property bool trailingMessagesRefresh: false
  property bool sending: false
  property bool hasOlderMessages: false
  property bool hasMoreChats: false
  // A failed page pauses automatic pagination until a fresh refresh/reconnect.
  // Do not turn a viewport sentinel into a tight retry loop.
  property bool chatsPaginationBlocked: false
  property bool messagesPaginationBlocked: false
  property alias chatTextSize: preferences.textSize
  property string oldestCursor: ""
  property string chatsCursor: ""
  property bool chatsInitialized: false
  property var deletedChatIDs: ({})
  property var deletedMessageIDs: ({})
  property string draftText: ""
  property var draftAttachment: null
  property string replyToMessageID: ""
  property bool viewFocused: false
  property var viewOwner: null
  property bool viewAtLatest: true
  property var viewPositions: ({})
  property int sequence: 0
  property int chatGeneration: 0
  property int draftRevision: 0
  property bool restoringDraft: false
  property var pending: ({})
  property var localDrafts: ({})
  property var savedSendDrafts: ({})
  property var retiredSendDrafts: ({})
  readonly property var recoverableDrafts: savedSendDrafts[currentChatID] || []
  property var demoMessages: ({})
  signal openRequested(string chatID, string messageID)
  signal messagesUpdating()
  signal messagesLoaded(bool older)
  signal messageSent(string chatID)
  signal quotesUpdating()
  signal quotesUpdated()
  signal tokenStored()
  signal chatPriorityChanged(string chatID, bool lowPriority)

  BeeperAudioPlayback { id: audioPlayback; beeperData: root }

  PersistentProperties {
    id: preferences
    reloadableId: "messengerPreferences"
    property int textSize: Theme.beeperFont.body
  }
  function setChatTextSize(size) {
    chatTextSize = Math.max(14, Math.min(36, Math.round(size)));
  }
  function ensureWaveform(url) {
    if (demo || !connected || !url) return;
    const key = JSON.stringify(url);
    if (waveforms[key]) return;
    const cache = Object.assign({}, waveforms);
    if (waveformQueue.length >= 32) {
      delete cache[JSON.stringify(waveformQueue[0])];
      waveformQueue = waveformQueue.slice(1);
    }
    const finished = Object.keys(cache).filter(id => !cache[id].pending);
    if (finished.length >= 128) delete cache[finished[0]];
    cache[key] = {pending: true, peaks: []}; waveforms = cache;
    waveformQueue = waveformQueue.concat([url]);
    processWaveforms();
  }
  function processWaveforms() {
    if (waveformBusy || !connected || !waveformQueue.length) return;
    const url = waveformQueue[0], key = JSON.stringify(url);
    waveformQueue = waveformQueue.slice(1); waveformBusy = true;
    request("waveform", {url: url}, (result, error) => {
      waveforms = Object.assign({}, waveforms, {[key]: {pending: false, peaks: !error && result?.peaks ? result.peaks : []}});
      waveformBusy = false; Qt.callLater(processWaveforms);
    }, true);
  }
  onConnectedChanged: {
    if (connected) {
      const cache = Object.assign({}, waveforms);
      for (const key of Object.keys(cache)) if (!cache[key].pending && !cache[key].peaks.length) delete cache[key];
      waveforms = cache;
      Qt.callLater(processWaveforms);
      Qt.callLater(() => scheduleUnreadCounts(true));
    } else {
      navigationLoadTimer.stop();
      ++accountsGeneration; loadingAccounts = false;
      ++unreadCountsGeneration; unreadCountsTimer.stop();
      unreadCountsLoaded = false; lowPriorityUnreadCountsLoaded = false; loadingUnreadCounts = false;
    }
  }
  function unreadConversationCount(network) {
    if (demo) return chats.filter(chat => Format.isChatInView(chat, showLowPriority) && Format.isChatUnread(chat)
      && (network === "all" || Format.networkBadge(chat.network).key === network)).length;
    const counts = showLowPriority ? lowPriorityUnreadCounts : unreadCounts;
    let count = 0;
    for (const name of Object.keys(counts))
      if (network === "all" || Format.networkBadge(name).key === network) count += counts[name];
    return count;
  }
  function scheduleUnreadCounts(immediate = false) {
    if (demo || !connected) return;
    unreadCountsDirty = true; unreadCountsUrgent = unreadCountsUrgent || immediate;
    if (loadingUnreadCounts) return;
    if (unreadCountsTimer.running && !immediate) return;
    unreadCountsTimer.interval = immediate ? 0 : Math.max(150, 3000 - (Date.now() - lastUnreadCountsAttempt));
    unreadCountsTimer.restart();
  }
  function refreshUnreadCounts() {
    if (demo || !connected || loadingUnreadCounts) return;
    const generation = unreadCountsGeneration;
    unreadCountsDirty = false; unreadCountsUrgent = false;
    loadingUnreadCounts = true; lastUnreadCountsAttempt = Date.now();
    request("unreadCounts", {}, (result, error) => {
      if (generation !== unreadCountsGeneration || !connected) return;
      loadingUnreadCounts = false;
      if (!error && result?.counts && typeof result.counts === "object" && !Array.isArray(result.counts)) {
        unreadCounts = result.counts; unreadCountsLoaded = true;
        lowPriorityUnreadCountsLoaded = !!result.lowPriorityCounts && typeof result.lowPriorityCounts === "object" && !Array.isArray(result.lowPriorityCounts);
        if (lowPriorityUnreadCountsLoaded) lowPriorityUnreadCounts = result.lowPriorityCounts;
      } else { unreadCountsLoaded = false; lowPriorityUnreadCountsLoaded = false; }
      if (unreadCountsDirty) scheduleUnreadCounts(unreadCountsUrgent);
    }, true);
  }

  function refreshSenderColors() {
    if (currentChat?.type !== "group") { senderColors = ({}); return; }
    const identities = (currentChat.participants?.items || []).map(person => person.id).filter(Boolean);
    for (const message of messages) {
      if (!message.chatID || message.chatID === currentChatID) identities.push(Format.senderKey(message));
    }
    for (const entry of Object.values(quotedMessages))
      if (entry.state === "ready" && entry.message) identities.push(Format.senderKey(entry.message));
    const colors = Format.assignSenderColors(senderColorRegistry[currentChatID] || {}, identities, Theme.beeperSenderColors);
    // Preserve existing assignments when history or new participants arrive.
    senderColorRegistry[currentChatID] = colors;
    senderColors = colors;
  }
  onCurrentChatChanged: refreshSenderColors()
  onMessagesChanged: refreshSenderColors()
  onQuotedMessagesChanged: refreshSenderColors()

  function request(method, params, callback, quiet) {
    if (demo) { demoRequest(method, params || {}, callback); return; }
    if (!backend.running) { if (callback) callback(null, {message: "The messaging service is unavailable."}); return; }
    const id = ++sequence;
    pending[id] = {callback: callback, method: method, quiet: quiet === true};
    backend.write(JSON.stringify({id: id, method: method, params: params || {}}) + "\n");
  }
  function acceptLine(line) {
    let response;
    try { response = JSON.parse(line); } catch (_) { lastError = "Could not read the service response."; return; }
    if (response.event) {
      if (response.event === "status") {
        applyStatus(response.data);
      } else if (response.event === "chatsChanged") { refreshTimer.restart(); scheduleUnreadCounts(); }
      else if (response.event === "chatsDeleted") {
        const ids = new Set(response.data.ids || []);
        ids.forEach(id => { deletedChatIDs[id] = true; });
        if (ids.has(currentChatID)) { flushDraft(); ++chatGeneration; currentChatID = ""; messages = []; loadingMessages = false; }
        chats = chats.filter(chat => !ids.has(chat.id));
        scheduleUnreadCounts(true);
      }
      else if (response.event === "messagesChanged" && response.data.chatID === currentChatID) {
        invalidateQuotes(); messagesTimer.restart();
      }
      else if (response.event === "messagesDeleted") {
        const chatID = response.data.chatID;
        const ids = new Set(response.data.ids || []);
        const deleted = deletedMessageIDs[chatID] || {};
        ids.forEach(id => { deleted[id] = true; });
        deletedMessageIDs = Object.assign({}, deletedMessageIDs, {[chatID]: deleted});
        if (chatID === currentChatID) messages = messages.filter(message => !ids.has(message.id));
      } else if (response.event === "sendFailed" || response.event === "warning") lastError = response.data.message || response.data.error || "An action failed. Check the conversation before trying again.";
      else if (response.event === "pendingResolved") { refreshTimer.restart(); if (response.data.chatID === currentChatID) messagesTimer.restart(); }
      else if (response.event === "openChat") openRequested(response.data.chatID, response.data.messageID || "");
      return;
    }
    const operation = pending[response.id];
    if (!operation) return;
    delete pending[response.id];
    if (response.error && !operation.quiet) lastError = response.error.message || "The action failed.";
    if (operation.callback) operation.callback(response.result, response.error || null);
  }
  function applyStatus(result) {
    if (!result || !result.state) return;
    if (typeof result.revision === "number") {
      if (result.revision < statusRevision) return;
      statusRevision = result.revision;
    }
    const wasConnected = connected;
    state = result.state; statusMessage = result.message || "";
    if (connected && !wasConnected) refresh();
  }
  function initialize() {
    request("status", {}, (result, error) => {
      if (error || !result) return;
      applyStatus(result);
    });
  }
  function retryConnection() {
    if (savingToken) return;
    lastError = "";
    request("reconnect", {}, (result, error) => { if (!error) applyStatus(result); });
  }
  function connectToken(token) {
    if (savingToken) return;
    lastError = ""; savingToken = true;
    request("connect", {token: token}, (result, error) => {
      savingToken = false;
      if (error) { initialize(); return; }
      applyStatus(result);
      tokenStored();
    });
  }
  function refresh() {
    invalidateQuotes();
    scheduleUnreadCounts(true);
    refreshAccounts();
    refreshChats(false);
    if (currentChatID) loadMessages(false);
  }
  function refreshAccounts() {
    if (!connected || loadingAccounts) return;
    const generation = accountsGeneration;
    loadingAccounts = true;
    request("accounts", {}, (result, error) => {
      if (generation !== accountsGeneration || !connected) return;
      loadingAccounts = false;
      const rows = Array.isArray(result) ? result : result?.items;
      if (!error && Array.isArray(rows)) accounts = rows;
    }, true);
  }
  function refreshChats(older) {
    if (older && (!hasMoreChats || !chatsCursor || chatsPaginationBlocked)) return;
    if (loading) { if (!older) trailingChatsRefresh = true; return; }
    if (!older) chatsPaginationBlocked = false;
    const cursor = older ? chatsCursor : "";
    const revision = chatsRevision;
    loading = true;
    request("chats", older ? {cursor: cursor, direction: "before"} : {}, (result, error) => {
      // Discard a read started before a successful priority change, then read
      // again. Later Beeper snapshots remain authoritative, including edits
      // made from another client; no placement override is kept locally.
      if (revision !== chatsRevision) {
        loading = false; trailingChatsRefresh = false;
        Qt.callLater(() => refreshChats(false));
        return;
      }
      if (trailingChatsRefresh) { trailingChatsRefresh = false; Qt.callLater(() => refreshChats(false)); }
      if (error || !result) { chatsPaginationBlocked = true; loading = false; return; }
      const rows = (result.items || []).filter(chat => !deletedChatIDs[chat.id]);
      if (older) { const ids = new Set(chats.map(chat => chat.id)); chats = chats.concat(rows.filter(chat => !ids.has(chat.id))); }
      else { const ids = new Set(rows.map(chat => chat.id)); chats = rows.concat(chats.filter(chat => !ids.has(chat.id))); }
      if (older || !chatsInitialized) {
        chatsCursor = result.oldestCursor || "";
        hasMoreChats = !!result.hasMore && !!chatsCursor && chatsCursor !== cursor;
      }
      chatsInitialized = true;
      loading = false;
    });
  }
  function selectChat(chatID, messageID, deferHistory = false) {
    targetMessageID = messageID || "";
    if (!chatID) return;
    const chat = chats.find(item => item.id === chatID);
    // Explicit targets (including notifications) must be visible in the list.
    if (chat && !Format.isChatInView(chat, showLowPriority)) showLowPriority = !showLowPriority;
    if (networkFilter !== "all" && (!chat || Format.networkBadge(chat.network).key !== networkFilter)) networkFilter = "all";
    if (chatID === currentChatID) {
      if (targetMessageID) {
        if (historyLoadPending) loadMessages(false);
        else if (!loadingMessages) messagesLoaded(false);
      }
      return;
    }
    navigationLoadTimer.stop();
    flushDraft();
    ++chatGeneration;
    quotedMessages = ({});
    currentChatID = chatID; messages = []; loadingMessages = false; trailingMessagesRefresh = false; hasOlderMessages = false; oldestCursor = ""; messagesPaginationBlocked = false;
    restoringDraft = true;
    const saved = localDrafts[chatID] || {};
    draftText = saved.text || ""; draftAttachment = saved.attachment || null; replyToMessageID = saved.replyToMessageID || "";
    restoringDraft = false;
    const generation = chatGeneration, revision = draftRevision;
    request("getDraft", {chatID: chatID}, (result, error) => {
      if (error || !result || generation !== chatGeneration) return;
      const recovered = mergeSavedSendDrafts(chatID, result.savedDrafts || []);
      if (revision !== draftRevision) {
        if (recovered) persistChatDraft(chatID);
        return;
      }
      restoringDraft = true;
      draftText = result.text || ""; draftAttachment = result.attachment || null; replyToMessageID = result.replyToMessageID || "";
      restoringDraft = false;
    });
    // Selection/drafts change immediately. During rapid sidebar navigation,
    // fetch only the conversation where the user pauses, not every row crossed.
    if (deferHistory && !demo && navigationLoadDelay > 0) navigationLoadTimer.restart();
    else loadMessages(false);
    updateView();
  }
  function clearSelection() {
    navigationLoadTimer.stop();
    flushDraft();
    ++chatGeneration;
    quotedMessages = ({});
    currentChatID = ""; targetMessageID = ""; messages = [];
    loadingMessages = false; trailingMessagesRefresh = false; hasOlderMessages = false; oldestCursor = ""; messagesPaginationBlocked = false;
    restoringDraft = true;
    draftText = ""; draftAttachment = null; replyToMessageID = "";
    restoringDraft = false;
    viewFocused = false; updateView(); messagesLoaded(false);
  }
  function loadMessages(older) {
    if (!currentChatID) return;
    if (!older) navigationLoadTimer.stop();
    if (older && (!hasOlderMessages || !oldestCursor || messagesPaginationBlocked)) return;
    if (loadingMessages) { if (!older) trailingMessagesRefresh = true; return; }
    if (!older) messagesPaginationBlocked = false;
    const generation = chatGeneration, chatID = currentChatID, cursor = older ? oldestCursor : "";
    loadingMessages = true;
    const params = {chatID: chatID};
    if (older) { params.cursor = cursor; params.direction = "before"; }
    request("messages", params, (result, error) => {
      if (generation !== chatGeneration) return;
      if (trailingMessagesRefresh) { trailingMessagesRefresh = false; Qt.callLater(() => { if (generation === chatGeneration) loadMessages(false); }); }
      if (error || !result) { messagesPaginationBlocked = true; loadingMessages = false; return; }
      messagesUpdating();
      const deleted = deletedMessageIDs[chatID] || {};
      messages = Format.mergeMessages(messages, result.items || []).filter(message => !deleted[message.id]);
      if (older || !oldestCursor) {
        oldestCursor = result.oldestCursor || "";
        hasOlderMessages = !!result.hasMore && !!oldestCursor && oldestCursor !== cursor;
      }
      loadingMessages = false;
      messagesLoaded(older);
    });
  }
  function toggleMessageReaction(message, reaction) {
    const chat = currentChat, chatID = currentChatID;
    if (!connected || !message?.id || !reaction || !Format.supports(chat, "reaction", message)) return;
    if (message.chatID && message.chatID !== chatID) return;
    reaction = Format.allowedReaction(chat, reaction);
    if (!reaction) {
      lastError = "This reaction is not supported in this conversation."; return;
    }
    const key = JSON.stringify([chatID, message.id]);
    let operation = reactionOperations[key];
    if (!operation) {
      const selfIDs = Format.selfParticipantIDs(chat, accounts);
      const keys = Format.ownReactionKeys(message, selfIDs);
      operation = {key: key, chatID: chatID, messageID: message.id, selfIDs: selfIDs,
        keys: keys, desired: keys.length === 1 ? keys[0] : "", busy: false, refreshing: false, revision: 0};
      reactionOperations[key] = operation;
    }
    operation.desired = Format.reactionIdentity(operation.desired) === Format.reactionIdentity(reaction) ? "" : reaction;
    ++operation.revision;
    processReaction(operation);
  }
  function processReaction(operation) {
    if (reactionOperations[operation.key] !== operation || operation.busy) return;
    if (!connected) { delete reactionOperations[operation.key]; return; }
    const previous = operation.keys.find(key => Format.reactionIdentity(key) !== Format.reactionIdentity(operation.desired));
    const reaction = previous || (operation.desired && !operation.keys.some(key => Format.reactionIdentity(key) === Format.reactionIdentity(operation.desired)) ? operation.desired : "");
    if (!reaction) { refreshReaction(operation); return; }
    const remove = !!previous;
    operation.busy = true;
    request("react", {chatID: operation.chatID, messageID: operation.messageID, reactionKey: reaction, remove: remove}, (result, error) => {
      operation.busy = false;
      if (reactionOperations[operation.key] !== operation) return;
      if (error) { delete reactionOperations[operation.key]; return; }
      operation.keys = remove ? operation.keys.filter(key => key !== reaction) : operation.keys.concat([reaction]);
      if (currentChatID === operation.chatID && operation.selfIDs.length) {
        messagesUpdating();
        messages = messages.map(message => message.id === operation.messageID
          ? Format.withOwnReactions(message, operation.selfIDs, operation.keys) : message);
        messagesLoaded(false);
      }
      processReaction(operation);
    });
  }
  function refreshReaction(operation) {
    if (currentChatID !== operation.chatID) { delete reactionOperations[operation.key]; return; }
    if (operation.refreshing) return;
    operation.refreshing = true;
    const revision = operation.revision;
    // Refresh the actual target, which may be outside the newest history page.
    request("message", {chatID: operation.chatID, messageID: operation.messageID}, (result, error) => {
      operation.refreshing = false;
      if (reactionOperations[operation.key] !== operation) return;
      if (revision !== operation.revision) { processReaction(operation); return; }
      delete reactionOperations[operation.key];
      if (error || !result || result.id !== operation.messageID || currentChatID !== operation.chatID
          || result.chatID && result.chatID !== operation.chatID) return;
      // A queued API mutation may not be reflected in the first read yet.
      const keys = Format.ownReactionKeys(result, operation.selfIDs);
      if (operation.selfIDs.length && (keys.length !== operation.keys.length
          || keys.some(key => !operation.keys.some(own => Format.reactionIdentity(own) === Format.reactionIdentity(key))))) return;
      messagesUpdating();
      messages = messages.map(message => message.id === operation.messageID ? Object.assign({}, message, result) : message);
      messagesLoaded(false);
    }, true);
  }
  function quote(messageID) {
    if (!messageID) return {state: "missing", message: null};
    if (deletedMessageIDs[currentChatID]?.[messageID]) return {state: "missing", message: null};
    const loaded = messages.find(message => message.id === messageID);
    if (loaded) return {state: loaded.isDeleted || loaded.isHidden ? "missing" : "ready", message: loaded};
    return quotedMessages[messageID] || {state: "idle", message: null};
  }
  function invalidateQuotes() {
    // Preserve in-flight requests; refresh cached originals after edits/reconnect.
    const pendingQuotes = {};
    for (const id of Object.keys(quotedMessages))
      if (quotedMessages[id].state === "loading") pendingQuotes[id] = quotedMessages[id];
    replaceQuotes(pendingQuotes);
  }
  function replaceQuotes(cache) {
    // Quote text can change row heights after the list is laid out. Let views
    // save their anchor before publishing it, including the just-sent end row.
    quotesUpdating(); quotedMessages = cache; quotesUpdated();
  }
  function ensureQuote(messageID) {
    if (!currentChatID || !messageID || !connected || quote(messageID).state !== "idle") return;
    const generation = chatGeneration, chatID = currentChatID;
    quotedMessages = Object.assign({}, quotedMessages, {[messageID]: {state: "loading", message: null}});
    // The public retrieve-message endpoint avoids paging the entire history.
    // A missing original is local to its quote, not an error banner for the chat.
    request("message", {chatID: chatID, messageID: messageID}, (result, error) => {
      if (generation !== chatGeneration) return;
      const unavailable = error || !result?.id || result.isDeleted || result.isHidden
        || (result.chatID && result.chatID !== chatID);
      replaceQuotes(Object.assign({}, quotedMessages, {[messageID]: {
        state: unavailable ? "missing" : "ready", message: unavailable ? null : result
      }}));
    }, true);
  }
  function draftChanged() {
    if (restoringDraft || !currentChatID) return;
    ++draftRevision;
    localDrafts[currentChatID] = {text: draftText, attachment: draftAttachment, replyToMessageID: replyToMessageID};
    draftTimer.restart();
  }
  function flushDraft(callback) {
    draftTimer.stop();
    if (currentChatID) persistChatDraft(currentChatID, callback);
  }
  function draftSnapshot() {
    return {text: draftText, attachment: draftAttachment, replyToMessageID: replyToMessageID};
  }
  function persistChatDraft(chatID, callback) {
    if (currentChatID === chatID) { draftTimer.stop(); localDrafts[chatID] = draftSnapshot(); }
    request("saveDraft", Object.assign({chatID: chatID}, localDrafts[chatID] || {},
      {savedDrafts: savedSendDrafts[chatID] || []}), callback);
  }
  function hasDraftContent(draft) {
    return !!draft && (!!draft.text || !!draft.attachment || !!draft.replyToMessageID);
  }
  function replaceDraft(chatID, draft) {
    const value = {text: draft.text || "", attachment: draft.attachment || null, replyToMessageID: draft.replyToMessageID || ""};
    localDrafts[chatID] = value;
    if (currentChatID !== chatID) return;
    restoringDraft = true;
    draftText = value.text; draftAttachment = value.attachment; replyToMessageID = value.replyToMessageID;
    restoringDraft = false; draftChanged();
  }
  function saveSendDraft(chatID, draft) {
    const saved = Object.assign({id: Date.now() + "-" + (++sequence)}, draft);
    savedSendDrafts = Object.assign({}, savedSendDrafts, {[chatID]: (savedSendDrafts[chatID] || []).concat([saved])});
    return saved.id;
  }
  function retireSendDraft(chatID, id) {
    retiredSendDrafts[id] = true;
    savedSendDrafts = Object.assign({}, savedSendDrafts, {[chatID]: (savedSendDrafts[chatID] || []).filter(draft => draft.id !== id)});
  }
  function mergeSavedSendDrafts(chatID, drafts) {
    const existing = savedSendDrafts[chatID] || [], ids = new Set(existing.map(draft => draft.id));
    const recovered = [];
    for (const draft of Array.isArray(drafts) ? drafts : []) {
      if (!draft?.id || retiredSendDrafts[draft.id] || ids.has(draft.id) || !hasDraftContent(draft)) continue;
      recovered.push(draft); ids.add(draft.id);
    }
    if (recovered.length) savedSendDrafts = Object.assign({}, savedSendDrafts, {[chatID]: existing.concat(recovered)});
    return recovered.length > 0;
  }
  function restoreSavedSendDraft() {
    if (sending || !currentChatID || !recoverableDrafts.length) return;
    const chatID = currentChatID, saved = recoverableDrafts[0], current = draftSnapshot();
    // Explicit recovery swaps drafts; it never overwrites the next message.
    if (hasDraftContent(current)) saveSendDraft(chatID, current);
    retireSendDraft(chatID, saved.id);
    replaceDraft(chatID, saved); persistChatDraft(chatID);
  }
  function markChatRead(chatID, messageID) {
    if (!chatID) return;
    const params = {chatID: chatID};
    if (messageID) params.messageID = messageID;
    request("read", params, (result, error) => {
      if (!error) { applyReadState(chatID, result); refreshChats(false); scheduleUnreadCounts(true); }
    });
  }
  function markChatUnread(chatID) {
    if (!chatID) return;
    request("unread", {chatID: chatID}, (result, error) => {
      if (!error) { applyReadState(chatID, result); refreshChats(false); scheduleUnreadCounts(true); }
    });
  }
  function applyReadState(chatID, result) {
    if (!result || result.id !== chatID || deletedChatIDs[chatID]) return;
    // Update only read state in place; a partial reply must not erase the
    // conversation's title, network or other fields used by sidebar filters.
    const changes = {};
    if (typeof result.unreadCount === "number") changes.unreadCount = result.unreadCount;
    if (typeof result.isMarkedUnread === "boolean") changes.isMarkedUnread = result.isMarkedUnread;
    chats = chats.map(chat => chat.id === chatID ? Object.assign({}, chat, changes) : chat);
  }
  function setChatLowPriority(chatID, lowPriority) {
    const chat = chats.find(item => item.id === chatID);
    if (!connected || !chat || lowPriorityPending[chatID] || typeof lowPriority !== "boolean") return;
    lastError = "";
    lowPriorityPending = Object.assign({}, lowPriorityPending, {[chatID]: true});
    request("updateChat", {chatID: chatID, changes: {isLowPriority: lowPriority}}, (result, error) => {
      const pending = Object.assign({}, lowPriorityPending); delete pending[chatID]; lowPriorityPending = pending;
      if (error || deletedChatIDs[chatID]) return;
      ++chatsRevision;
      const changes = {isLowPriority: typeof result?.isLowPriority === "boolean" ? result.isLowPriority : lowPriority};
      if (typeof result?.isMuted === "boolean") changes.isMuted = result.isMuted;
      chats = chats.map(item => item.id === chatID ? Object.assign({}, item, changes) : item);
      chatPriorityChanged(chatID, changes.isLowPriority);
      refreshChats(false); scheduleUnreadCounts(true);
    });
  }
  function sendMessage() {
    if (!currentChatID || sending || !connected || (!draftText.trim() && !draftAttachment)) return;
    const chatID = currentChatID, snapshot = draftSnapshot();
    // Snapshot the boundary before sending so a message arriving during the
    // request stays unread, even if the user switches conversations meanwhile.
    const readThroughID = currentChat?.preview?.id || messages[messages.length - 1]?.id || "";
    sending = true; lastError = "";
    const savedID = saveSendDraft(chatID, snapshot);
    // Start a fresh composer synchronously. Preserve the submitted payload on
    // disk before dispatch, independently of the next draft and any late reply.
    replaceDraft(chatID, {}); persistChatDraft(chatID);
    request("send", Object.assign({chatID: chatID}, snapshot), (result, error) => {
      sending = false;
      if (error) {
        if (!deletedChatIDs[chatID]) {
          const current = currentChatID === chatID ? draftSnapshot() : localDrafts[chatID];
          if (!hasDraftContent(current)) { retireSendDraft(chatID, savedID); replaceDraft(chatID, snapshot); }
          persistChatDraft(chatID);
        }
        return;
      }
      retireSendDraft(chatID, savedID);
      if (!deletedChatIDs[chatID]) persistChatDraft(chatID);
      viewPositions[chatID] = {atLatest: true};
      markChatRead(chatID, readThroughID);
      messageSent(chatID);
      if (currentChatID === chatID) loadMessages(false);
      refreshChats(false);
    });
  }
  function stageAttachment(path) {
    const chatID = currentChatID;
    request("stageAttachment", {path: path}, (result, error) => {
      if (error || !result) return;
      if (currentChatID === chatID) draftAttachment = result;
      else {
        const saved = Object.assign({}, localDrafts[chatID] || {}, {chatID: chatID, attachment: result});
        localDrafts[chatID] = saved; request("saveDraft", saved);
      }
    });
  }
  function pasteAttachment() {
    const chatID = currentChatID;
    request("clipboardAttachment", {}, (result, error) => { if (!error && result && result.path && chatID === currentChatID) draftAttachment = result; });
  }
  function clearAttachment() {
    const attachment = draftAttachment;
    draftAttachment = null;
    if (attachment) flushDraft((result, error) => { if (!error) request("discardAttachment", {path: attachment.path}); });
  }
  function updateView() { request("setView", {chatID: currentChatID, focused: viewFocused, atLatest: viewAtLatest}); }
  onViewFocusedChanged: updateView()
  onViewAtLatestChanged: updateView()
  onDraftTextChanged: draftChanged()
  onDraftAttachmentChanged: draftChanged()
  onReplyToMessageIDChanged: draftChanged()
  Component.onCompleted: { if (demo) initializeDemo(); }
  Component.onDestruction: flushDraft()

  Timer { id: draftTimer; interval: 300; onTriggered: root.flushDraft() }
  // Account status has no dedicated public WebSocket event. One shared poll
  // keeps failures and recoveries current, even while a chat receives no messages.
  Timer {
    interval: 5000; repeat: true
    running: root.enabled && !root.demo && root.connected
    onTriggered: root.refreshAccounts()
  }
  Timer { id: unreadCountsTimer; interval: 150; onTriggered: root.refreshUnreadCounts() }
  Timer { id: navigationLoadTimer; interval: root.navigationLoadDelay; onTriggered: root.loadMessages(false) }
  Timer { id: refreshTimer; interval: 150; onTriggered: root.refreshChats(false) }
  Timer { id: messagesTimer; interval: 100; onTriggered: root.loadMessages(false) }
  Timer { id: restartTimer; interval: 3000; onTriggered: if (root.enabled && !root.demo) backend.running = true }
  Process {
    id: backend
    command: root.command
    running: root.enabled && !root.demo
    stdinEnabled: true
    onStarted: {
      root.statusRevision = -1;
      root.state = "loading-token";
      root.statusMessage = "Restoring your saved access token…";
      root.initialize();
    }
    stdout: SplitParser { onRead: data => root.acceptLine(data) }
    onExited: {
      root.state = "offline"; root.statusMessage = "Reconnecting to the service…";
      const callbacks = root.pending; root.pending = ({});
      for (const id in callbacks) if (callbacks[id].callback) callbacks[id].callback(null, {message: "Connection interrupted. Check the result before sending again."});
      restartTimer.restart();
    }
  }

  // Deterministic, local-only visual fixture. It never starts the API process.
  function initializeDemo() {
    state = "demo";
    accounts = [{id: "signal", network: "Signal"}, {id: "whatsapp", network: "WhatsApp"}, {id: "telegram", network: "Telegram"}];
    const now = new Date();
    chats = [
      {id: "studio", title: "Atelier du dimanche", type: "group", network: "Signal", accountID: "signal", unreadCount: 2, preview: {text: "Camille : cette lumière ✨"}, isPinned: true,
        participants: {total: 3, hasMore: false, items: [{id: "camille", fullName: "Camille"}, {id: "noe", fullName: "Noé"}, {id: "self", fullName: "You", isSelf: true}]}},
      {id: "lea", title: "Léa Martin", network: "WhatsApp", accountID: "whatsapp", unreadCount: 0, preview: {text: "On se retrouve à 18 h ?"}},
      {id: "design", title: "Design & café", network: "Telegram", accountID: "telegram", unreadCount: 4, preview: {text: "Une idée pour le week-end"}},
      {id: "alex", title: "Alex", network: "Signal", accountID: "signal", unreadCount: 0, preview: {text: "Voice message"}},
      {id: "maison", title: "À la maison", network: "WhatsApp", accountID: "whatsapp", unreadCount: 0, isMuted: true, preview: {text: "À tout à l’heure ♡"}}];
    demoMessages = {studio: [
      {id: "1", chatID: "studio", senderName: "Camille", text: "J’ai trouvé un petit atelier près du canal pour dimanche. Vous venez ?", timestamp: now.toISOString(), isSender: false},
      {id: "2", chatID: "studio", senderName: "Moi", text: "Oui ! Un carnet, un café, et rien de prévu. Ça me va très bien.", linkedMessageID: "1", timestamp: now.toISOString(), isSender: true, seen: {camille: true, noe: now.toISOString()}},
      {id: "3", chatID: "studio", senderName: "Camille", text: "Exactement le programme 🌿", linkedMessageID: "2", timestamp: now.toISOString(), isSender: false, reactions: [{participantID: "self", reactionKey: "💜", emoji: true}, {participantID: "noe", reactionKey: "👍", emoji: true}]},
      {id: "4", chatID: "studio", senderName: "Noé", text: "Je vous rejoins vers 10 h. Je ramène les croissants !", timestamp: now.toISOString(), isSender: false}]};
    const illustration = '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="460" viewBox="0 0 900 460"><defs><linearGradient id="sky" x2="0" y2="1"><stop stop-color="#8aadf4"/><stop offset="1" stop-color="#f5bde6"/></linearGradient></defs><rect width="900" height="460" fill="url(#sky)"/><circle cx="685" cy="120" r="58" fill="#eed49f"/><path d="M0 285 Q180 220 400 285 T900 275 V460 H0Z" fill="#363a4f"/><path d="M0 315 Q240 260 410 320 T900 310 V460 H0Z" fill="#24273a"/><path d="M270 460 L455 292 L495 292 L655 460Z" fill="#91d7e3" opacity=".75"/><path d="M0 365 Q190 320 285 348 L205 460 H0Z" fill="#a6da95"/><path d="M675 460 L585 340 Q775 290 900 325 V460Z" fill="#8bd5ca"/><text x="40" y="70" fill="#24273a" font-family="sans-serif" font-size="17" letter-spacing="4">DIMANCHE AU CANAL</text></svg>';
    demoMessages.studio.splice(1, 0, {id: "photo", chatID: "studio", senderName: "Camille", text: "Le coin idéal pour une pause.", isSender: false, attachments: [{id: "demo-image", type: "img", mimeType: "image/svg+xml", fileName: "illustration-du-canal.svg", srcURL: "data:image/svg+xml;charset=utf-8," + encodeURIComponent(illustration)}]});
    demoMessages.design = [{id: "demo-file", chatID: "design", senderName: "Alex", text: "Le programme de l’atelier — document de démonstration.", timestamp: now.toISOString(), attachments: [{type: "unknown", fileName: "Programme de l’atelier.pdf", mimeType: "application/pdf", fileSize: 245760}]}];
    demoMessages.studio = demoMessages.studio.map((message, index) => Object.assign({}, message, {timestamp: new Date(now.getTime() - (4 - index) * 180000).toISOString()}));
    selectChat("studio");
  }
  function demoRequest(method, params, callback) {
    let result = {};
    if (method === "status") result = {state: "demo"};
    else if (method === "accounts") result = {items: accounts};
    else if (method === "chats") result = {items: chats};
    else if (method === "messages") result = {items: demoMessages[params.chatID] || []};
    else if (method === "message") result = (demoMessages[params.chatID] || []).find(message => message.id === params.messageID) || {};
    else if (method === "getDraft") result = localDrafts[params.chatID] || {};
    else if (method === "send") {
      const rows = (demoMessages[params.chatID] || []).slice();
      rows.push({id: "demo-" + (++sequence), chatID: params.chatID, text: params.text, senderName: "Moi", isSender: true, linkedMessageID: params.replyToMessageID || "", timestamp: new Date().toISOString(), attachments: params.attachment ? [params.attachment] : []});
      demoMessages[params.chatID] = rows;
    } else if (method === "delete") {
      demoMessages[params.chatID] = (demoMessages[params.chatID] || []).filter(message => message.id !== params.messageID);
    } else if (method === "edit") {
      demoMessages[params.chatID] = (demoMessages[params.chatID] || []).map(message => message.id === params.messageID ? Object.assign({}, message, {text: params.text}) : message);
    } else if (method === "react") {
      demoMessages[params.chatID] = (demoMessages[params.chatID] || []).map(message => {
        if (message.id !== params.messageID) return message;
        const reactions = (message.reactions || []).filter(reaction => reaction.id !== "demo-own");
        if (!params.remove) reactions.push({id: "demo-own", participantID: "self", reactionKey: params.reactionKey, emoji: true});
        return Object.assign({}, message, {reactions: reactions});
      });
    } else if (method === "read") {
      const rows = demoMessages[params.chatID] || [];
      const boundary = params.messageID ? rows.findIndex(message => message.id === params.messageID) : rows.length - 1;
      if (params.messageID && boundary < 0) {
        if (callback) Qt.callLater(() => callback(null, {message: "The read boundary is unavailable."}));
        return;
      }
      demoMessages[params.chatID] = rows.map((message, index) => index <= boundary ? Object.assign({}, message, {isUnread: false}) : message);
      const unread = demoMessages[params.chatID].filter(message => !message.isSender && message.isUnread !== false).length;
      chats = chats.map(chat => chat.id === params.chatID ? Object.assign({}, chat, {unreadCount: unread, isMarkedUnread: false}) : chat);
      result = chats.find(chat => chat.id === params.chatID) || {};
    } else if (method === "unread") {
      chats = chats.map(chat => chat.id === params.chatID ? Object.assign({}, chat, {isMarkedUnread: true}) : chat);
      result = chats.find(chat => chat.id === params.chatID) || {};
    } else if (method === "updateChat") {
      chats = chats.map(chat => chat.id === params.chatID ? Object.assign({}, chat, params.changes) : chat);
      result = chats.find(chat => chat.id === params.chatID) || {};
    } else if (method === "stageAttachment") result = {path: params.path, srcURL: params.path, type: "file", fileName: params.path.split("/").pop()};
    else if (method === "search") {
      const words = String(params.query || "").trim().toLowerCase().split(/\s+/).filter(Boolean);
      const rows = Object.values(demoMessages).reduce((all, page) => all.concat(page), []);
      result = {items: rows.filter(message => (!params.chatID || message.chatID === params.chatID)
        && words.every(word => Format.text(message).toLowerCase().includes(word))), hasMore: false};
    }
    if (callback) Qt.callLater(() => callback(result, null));
  }
}
