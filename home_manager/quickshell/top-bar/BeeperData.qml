import QtQuick
import Quickshell
import Quickshell.Io
import "components/BeeperFormat.js" as Format
import "components/Theme.js" as Theme

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
  property var chats: []
  property var messages: []
  property var searchResults: []
  property string currentChatID: ""
  property string targetMessageID: ""
  readonly property var currentChat: chats.find(chat => chat.id === currentChatID) || null
  property var senderColorRegistry: ({})
  property var senderColors: ({})
  property bool loading: false
  property bool loadingMessages: false
  property bool trailingChatsRefresh: false
  property bool trailingMessagesRefresh: false
  property bool sending: false
  property bool hasOlderMessages: false
  property bool hasMoreChats: false
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
  property bool followLatest: true
  property var readMarkers: ({})
  property var viewPositions: ({})
  property int sequence: 0
  property int chatGeneration: 0
  property int draftRevision: 0
  property bool restoringDraft: false
  property var pending: ({})
  property var localDrafts: ({})
  property var demoMessages: ({})
  signal openRequested(string chatID, string messageID)
  signal messagesUpdating()
  signal messagesLoaded(bool older)
  signal tokenStored()

  function refreshSenderColors() {
    if (currentChat?.type !== "group") { senderColors = ({}); return; }
    const identities = (currentChat.participants?.items || []).map(person => person.id).filter(Boolean);
    for (const message of messages) {
      if (!message.chatID || message.chatID === currentChatID) identities.push(Format.senderKey(message));
    }
    const colors = Format.assignSenderColors(senderColorRegistry[currentChatID] || {}, identities, Theme.beeperSenderColors);
    // Preserve existing assignments when history or new participants arrive.
    senderColorRegistry[currentChatID] = colors;
    senderColors = colors;
  }
  onCurrentChatChanged: refreshSenderColors()
  onMessagesChanged: refreshSenderColors()

  function request(method, params, callback) {
    if (demo) { demoRequest(method, params || {}, callback); return; }
    if (!backend.running) { if (callback) callback(null, {message: "Le service de messagerie est indisponible."}); return; }
    const id = ++sequence;
    pending[id] = {callback: callback, method: method};
    backend.write(JSON.stringify({id: id, method: method, params: params || {}}) + "\n");
  }
  function acceptLine(line) {
    let response;
    try { response = JSON.parse(line); } catch (_) { lastError = "Réponse du service illisible."; return; }
    if (response.event) {
      if (response.event === "status") {
        applyStatus(response.data);
      } else if (response.event === "chatsChanged") refreshTimer.restart();
      else if (response.event === "chatsDeleted") {
        const ids = new Set(response.data.ids || []);
        ids.forEach(id => { deletedChatIDs[id] = true; });
        if (ids.has(currentChatID)) { flushDraft(); ++chatGeneration; currentChatID = ""; messages = []; loadingMessages = false; }
        chats = chats.filter(chat => !ids.has(chat.id));
      }
      else if (response.event === "messagesChanged" && response.data.chatID === currentChatID) messagesTimer.restart();
      else if (response.event === "messagesDeleted") {
        const chatID = response.data.chatID;
        const ids = new Set(response.data.ids || []);
        const deleted = deletedMessageIDs[chatID] || {};
        ids.forEach(id => { deleted[id] = true; });
        deletedMessageIDs[chatID] = deleted;
        if (chatID === currentChatID) messages = messages.filter(message => !ids.has(message.id));
      } else if (response.event === "sendFailed" || response.event === "warning") lastError = response.data.message || response.data.error || "Une action n’a pas abouti. Vérifie la conversation avant de réessayer.";
      else if (response.event === "pendingResolved") { refreshTimer.restart(); if (response.data.chatID === currentChatID) messagesTimer.restart(); }
      else if (response.event === "openChat") openRequested(response.data.chatID, response.data.messageID || "");
      return;
    }
    const operation = pending[response.id];
    if (!operation) return;
    delete pending[response.id];
    if (response.error) lastError = response.error.message || "L’action a échoué.";
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
    request("accounts", {}, (result, error) => { if (!error) accounts = result.items || result || []; });
    refreshChats(false);
    if (currentChatID) loadMessages(false);
  }
  function refreshChats(older) {
    if (loading) { if (!older) trailingChatsRefresh = true; return; }
    loading = true;
    request("chats", older ? {cursor: chatsCursor, direction: "before"} : {}, (result, error) => {
      loading = false;
      if (trailingChatsRefresh) { trailingChatsRefresh = false; Qt.callLater(() => refreshChats(false)); }
      if (error || !result) return;
      const rows = (result.items || []).filter(chat => !deletedChatIDs[chat.id]);
      if (older) { const ids = new Set(chats.map(chat => chat.id)); chats = chats.concat(rows.filter(chat => !ids.has(chat.id))); }
      else { const ids = new Set(rows.map(chat => chat.id)); chats = rows.concat(chats.filter(chat => !ids.has(chat.id))); }
      if (older || !chatsInitialized) { hasMoreChats = !!result.hasMore; chatsCursor = result.oldestCursor || ""; }
      chatsInitialized = true;
    });
  }
  function selectChat(chatID, messageID) {
    targetMessageID = messageID || "";
    if (!chatID) return;
    if (chatID === currentChatID) { if (targetMessageID) messagesLoaded(false); return; }
    flushDraft();
    ++chatGeneration;
    currentChatID = chatID; messages = []; loadingMessages = false; trailingMessagesRefresh = false; hasOlderMessages = false; oldestCursor = "";
    restoringDraft = true;
    const saved = localDrafts[chatID] || {};
    draftText = saved.text || ""; draftAttachment = saved.attachment || null; replyToMessageID = saved.replyToMessageID || "";
    restoringDraft = false;
    const generation = chatGeneration, revision = draftRevision;
    request("getDraft", {chatID: chatID}, (result, error) => {
      if (error || !result || generation !== chatGeneration || revision !== draftRevision) return;
      restoringDraft = true;
      draftText = result.text || ""; draftAttachment = result.attachment || null; replyToMessageID = result.replyToMessageID || "";
      restoringDraft = false;
    });
    loadMessages(false); updateView();
  }
  function loadMessages(older) {
    if (!currentChatID) return;
    if (loadingMessages) { if (!older) trailingMessagesRefresh = true; return; }
    const generation = chatGeneration, chatID = currentChatID;
    loadingMessages = true;
    const params = {chatID: chatID};
    if (older) { params.cursor = oldestCursor; params.direction = "before"; }
    request("messages", params, (result, error) => {
      if (generation !== chatGeneration) return;
      loadingMessages = false;
      if (trailingMessagesRefresh) { trailingMessagesRefresh = false; Qt.callLater(() => { if (generation === chatGeneration) loadMessages(false); }); }
      if (error || !result) return;
      followLatest = viewAtLatest;
      messagesUpdating();
      const deleted = deletedMessageIDs[chatID] || {};
      messages = Format.mergeMessages(messages, result.items || []).filter(message => !deleted[message.id]);
      if (older || !oldestCursor) { oldestCursor = result.oldestCursor || ""; hasOlderMessages = !!result.hasMore; }
      messagesLoaded(older);
    });
  }
  function draftChanged() {
    if (restoringDraft || !currentChatID) return;
    ++draftRevision;
    localDrafts[currentChatID] = {text: draftText, attachment: draftAttachment, replyToMessageID: replyToMessageID};
    draftTimer.restart();
  }
  function flushDraft(callback) {
    draftTimer.stop();
    if (currentChatID) {
      localDrafts[currentChatID] = draftSnapshot();
      request("saveDraft", Object.assign({chatID: currentChatID}, localDrafts[currentChatID]), callback);
    }
  }
  function draftSnapshot() {
    return {text: draftText, attachment: draftAttachment, replyToMessageID: replyToMessageID};
  }
  function sendMessage() {
    if (!currentChatID || sending || !connected || (!draftText.trim() && !draftAttachment)) return;
    const chatID = currentChatID, snapshot = draftSnapshot();
    sending = true; lastError = "";
    request("send", {chatID: chatID, text: draftText, attachment: draftAttachment, replyToMessageID: replyToMessageID}, (result, error) => {
      sending = false;
      if (error) return;
      const current = currentChatID === chatID ? draftSnapshot() : localDrafts[chatID];
      if (JSON.stringify(current) === JSON.stringify(snapshot)) {
        if (currentChatID === chatID) { draftText = ""; draftAttachment = null; replyToMessageID = ""; flushDraft(); }
        else {
          localDrafts[chatID] = {text: "", attachment: null, replyToMessageID: ""};
          request("saveDraft", Object.assign({chatID: chatID}, localDrafts[chatID]));
        }
      }
      loadMessages(false); refreshChats(false);
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
      root.statusMessage = "Récupération de l’accès enregistré…";
      root.initialize();
    }
    stdout: SplitParser { onRead: data => root.acceptLine(data) }
    onExited: {
      root.state = "offline"; root.statusMessage = "Reconnexion au service…";
      const callbacks = root.pending; root.pending = ({});
      for (const id in callbacks) if (callbacks[id].callback) callbacks[id].callback(null, {message: "Connexion interrompue. Vérifie le résultat avant de renvoyer."});
      restartTimer.restart();
    }
  }

  // Deterministic, local-only visual fixture. It never starts the API process.
  function initializeDemo() {
    state = "demo";
    accounts = [{id: "signal", network: "Signal"}, {id: "whatsapp", network: "WhatsApp"}, {id: "telegram", network: "Telegram"}];
    const now = new Date();
    chats = [
      {id: "studio", title: "Atelier du dimanche", type: "group", network: "Signal", accountID: "signal", unreadCount: 2, preview: {text: "Camille : cette lumière ✨"}, isPinned: true},
      {id: "lea", title: "Léa Martin", network: "WhatsApp", accountID: "whatsapp", unreadCount: 0, preview: {text: "On se retrouve à 18 h ?"}},
      {id: "design", title: "Design & café", network: "Telegram", accountID: "telegram", unreadCount: 4, preview: {text: "Une idée pour le week-end"}},
      {id: "alex", title: "Alex", network: "Signal", accountID: "signal", unreadCount: 0, preview: {text: "Message vocal"}},
      {id: "maison", title: "À la maison", network: "WhatsApp", accountID: "whatsapp", unreadCount: 0, isMuted: true, preview: {text: "À tout à l’heure ♡"}}];
    demoMessages = {studio: [
      {id: "1", chatID: "studio", senderName: "Camille", text: "J’ai trouvé un petit atelier près du canal pour dimanche. Vous venez ?", timestamp: now.toISOString(), isSender: false},
      {id: "2", chatID: "studio", senderName: "Moi", text: "Oui ! Un carnet, un café, et rien de prévu. Ça me va très bien.", timestamp: now.toISOString(), isSender: true},
      {id: "3", chatID: "studio", senderName: "Camille", text: "Exactement le programme 🌿", timestamp: now.toISOString(), isSender: false, reactions: [{reactionKey: "♡", count: 2}]},
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
    else if (method === "getDraft") result = localDrafts[params.chatID] || {};
    else if (method === "send") {
      const rows = (demoMessages[params.chatID] || []).slice();
      rows.push({id: "demo-" + (++sequence), chatID: params.chatID, text: params.text, senderName: "Moi", isSender: true, timestamp: new Date().toISOString(), attachments: params.attachment ? [params.attachment] : []});
      demoMessages[params.chatID] = rows;
    } else if (method === "delete") {
      demoMessages[params.chatID] = (demoMessages[params.chatID] || []).filter(message => message.id !== params.messageID);
    } else if (method === "edit") {
      demoMessages[params.chatID] = (demoMessages[params.chatID] || []).map(message => message.id === params.messageID ? Object.assign({}, message, {text: params.text}) : message);
    } else if (method === "updateChat") {
      chats = chats.map(chat => chat.id === params.chatID ? Object.assign({}, chat, params.changes) : chat);
    } else if (method === "stageAttachment") result = {path: params.path, srcURL: params.path, type: "file", fileName: params.path.split("/").pop()};
    else if (method === "search") result = {items: Object.values(demoMessages).flat().filter(message => message.text.toLowerCase().includes(params.query.toLowerCase()))};
    if (callback) Qt.callLater(() => callback(result, null));
  }
}
