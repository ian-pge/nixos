import QtQuick
import Quickshell
import Quickshell.Io
import "../../ui/Theme.js" as Theme
import "./AssistantFormat.js" as Format

// One instance serves every monitor. Each model has its own conversation,
// pi session and draft; this model shows the selected one. Qwen runs locally
// and read-only; OpenAI acts on the computer through pi.
Scope {
  id: root
  property list<string> command: ["quickshell-assistant"]
  property bool enabled: true
  readonly property var conversations: [
    {key: "qwen", title: "Qwen", label: "Qwen3.5 9B · Abliterated · Read-only", logo: Qt.resolvedUrl("assets/qwen/logo.png"), accent: Theme.flamingo, local: true,
     thinkingLevels: ["off", "high"], defaultThinking: "off"},
    {key: "openai", title: "OpenAI", label: "GPT-6.1 Sol · Full access", logo: Qt.resolvedUrl("assets/openai/logo.svg"), accent: Theme.usageAccent, local: false,
     thinkingLevels: ["low", "medium", "high", "xhigh"], defaultThinking: "medium"}
  ]
  property string conversation: "qwen"
  readonly property var current: conversations.find(item => item.key === conversation) || conversations[0]
  readonly property string title: current.title
  readonly property string modelLabel: current.label
  readonly property bool local: current.local
  readonly property bool available: backend.running
  // Saved per conversation by the backend; the default shows until it answers.
  property string savedThinkingLevel: ""
  property int thinkingRequests: 0
  readonly property var thinkingLevels: current.thinkingLevels
  readonly property string thinkingLevel: thinkingLevels.indexOf(savedThinkingLevel) >= 0 ? savedThinkingLevel : current.defaultThinking
  readonly property int thinkingIndex: thinkingLevels.indexOf(thinkingLevel)
  readonly property color thinkingColor: Format.thinkingColor(thinkingIndex, thinkingLevels.length)
  readonly property string thinkingName: Format.thinkingName(thinkingLevel, thinkingLevels)
  property var messages: []
  property real revision: -1
  property real resetRevision: 0
  property bool generating: false
  property bool unloading: false
  property bool resetting: false
  property bool unloadPending: false
  readonly property bool busy: resetting || unloading || unloadPending
  property bool sending: false
  property bool loadingMessages: false
  property bool hasOlderMessages: false
  property string oldestCursor: ""
  property bool paginationBlocked: false
  // Rejects pages and replies from before a reset, a switch or a restart.
  property int generation: 0
  property string draftText: ""
  property bool restoringDraft: false
  property int draftRevision: 0
  property string lastError: ""
  property var correction: null
  property string presentedCorrectionID: ""
  property string dismissedCorrectionID: ""
  property var correctionCalls: ({})
  property int correctionSequence: 0
  signal correctionPresented()
  signal correctionClosed(string reportID)
  function resolveCorrection(id, decision) {
    const call = correctionCalls[id];
    if (!call) return;
    call.decision = decision;
    if (decision === "reject" || call.result) {
      delete correctionCalls[id];
      call.callback(decision === "reject" ? {reportId:id, cancelled:true} : call.result, null);
    }
  }
  function decideCorrection(accept) {
    if (!correction) return;
    if (accept && correction.state === "running") return;
    if (!["running", "ready"].includes(correction.state)) { correctionClosed(correction.id); return; }
    request("decideCorrection", {reportId:correction.id, status:accept ? "accept" : "reject"}, null, true);
  }
  function dismissCorrection() {
    if (correction && ["running", "ready"].includes(correction.state)) {
      request("decideCorrection", {reportId:correction.id, status:"reject"}, null, true);
      resolveCorrection(correction.id, "reject");
    }
    dismissedCorrectionID = correction?.id || presentedCorrectionID;
    correction = null;
  }
  property var pending: ({})
  property int sequence: 0
  property alias textSize: preferences.textSize
  readonly property alias mathRenderer: mathRenderer
  signal messagesUpdating()
  signal messagesLoaded(bool older)
  signal messageSent()
  signal conversationReset()
  signal conversationSwitched()
  signal modelUnloaded()

  AssistantMath { id: mathRenderer }
  PersistentProperties {
    id: preferences
    reloadableId: "assistantPreferences"
    property int textSize: 18
  }
  function setTextSize(size) { textSize = Math.max(12, Math.min(32, Math.round(size))); }

  function request(method, params, callback, quiet) {
    if (!backend.running) {
      if (callback) Qt.callLater(() => callback(null, {message: "The assistant service is unavailable."}));
      return;
    }
    const id = ++sequence;
    pending[id] = {callback: callback, quiet: quiet === true};
    backend.write(JSON.stringify({id: id, method: method, params: params || {}}) + "\n");
  }
  function acceptLine(line) {
    let response;
    try { response = JSON.parse(line); } catch (_) { lastError = "Could not read the assistant service response."; return; }
    if (response.event) {
      if (response.event === "correctionChanged") {
        const state = response.data?.state;
        if (state === "accepted" || state === "dismissed")
          resolveCorrection(response.data.id, state === "accepted" ? "accept" : "reject");
        if (response.data?.id === dismissedCorrectionID) return;
        const firstUpdate = response.data?.id !== presentedCorrectionID;
        correction = response.data;
        if (state === "accepted" || state === "dismissed") { correctionClosed(correction.id); return; }
        if (firstUpdate) { presentedCorrectionID = correction.id; correctionPresented(); }
        return;
      }
      if (response.event === "changed") applySnapshot(response.data);
      else if (response.event === "warning") lastError = response.data?.message || "An assistant action failed.";
      return;
    }
    const operation = pending[response.id];
    if (!operation) return;
    delete pending[response.id];
    if (response.error && !operation.quiet) lastError = response.error.message || "The action failed.";
    if (operation.callback) operation.callback(response.result, response.error || null);
  }
  // Snapshots are revisioned: an older stream chunk never replaces a newer
  // one. Activity of the other conversation stays in its own history.
  function applySnapshot(result) {
    if (!result || typeof result.revision !== "number" || result.revision < revision) return;
    if ((result.conversation || "qwen") !== conversation) return;
    const reset = (result.resetRevision || 0) > resetRevision;
    resetRevision = result.resetRevision || 0;
    revision = result.revision;
    generating = result.generating === true;
    unloading = result.unloading === true;
    if (typeof result.thinkingLevel === "string" && !thinkingRequests) savedThinkingLevel = result.thinkingLevel;
    if (!Array.isArray(result.items)) return;
    messagesUpdating();
    if (reset) {
      ++generation;
      loadingMessages = false; paginationBlocked = false;
      hasOlderMessages = false; oldestCursor = "";
    }
    messages = Format.mergeMessages(reset ? [] : messages, result.items);
    if (typeof result.oldestCursor === "string" && (reset || !oldestCursor)) {
      oldestCursor = result.oldestCursor;
      hasOlderMessages = !!result.hasMore && !!oldestCursor;
    }
    if (reset) conversationReset();
    messagesLoaded(false);
  }
  // Show the selected conversation from scratch, with its own draft.
  function load(key, selectSaved) {
    const loadGeneration = ++generation, draftGeneration = draftRevision;
    loadingMessages = false;
    request("status", {conversation: key}, (result, error) => {
      if (error || !result || loadGeneration !== generation) return;
      if (selectSaved && result.selected && result.selected !== key) { switchTo(result.selected, false); return; }
      messagesUpdating();
      messages = [];
      oldestCursor = ""; hasOlderMessages = false; paginationBlocked = false;
      revision = -1; resetRevision = 0;
      applySnapshot(result);
      // A draft typed while the backend started wins over the saved one.
      if (draftGeneration === draftRevision) {
        restoringDraft = true; draftText = result.draft || ""; restoringDraft = false;
      }
    }, true);
  }
  function initialize() { load(conversation, true); }
  function switchTo(key, remember = true) {
    if (!conversations.some(item => item.key === key)) return;
    if (draftTimer.running) flushDraft();
    if (key !== conversation) {
      conversation = key;
      generating = false; unloading = false; resetting = false; unloadPending = false; sending = false;
      lastError = ""; savedThinkingLevel = ""; thinkingRequests = 0;
      restoringDraft = true; draftText = ""; restoringDraft = false;
      ++draftRevision;
      // Never show one model's messages under the other model's logo.
      messagesUpdating(); messages = []; hasOlderMessages = false; oldestCursor = "";
      messagesLoaded(false);
      conversationSwitched();
    }
    if (remember) request("select", {conversation: key}, null, true);
    load(key, false);
  }
  function cycleConversation(delta) {
    const index = conversations.findIndex(item => item.key === conversation);
    switchTo(conversations[(index + delta + conversations.length) % conversations.length].key);
  }
  function loadOlderMessages() {
    if (loadingMessages || !hasOlderMessages || !oldestCursor || paginationBlocked) return;
    const pageGeneration = generation, cursor = oldestCursor, key = conversation;
    loadingMessages = true;
    request("messages", {conversation: key, cursor: cursor}, (result, error) => {
      if (pageGeneration !== generation) return;
      loadingMessages = false;
      if (error || !result) { paginationBlocked = true; return; }
      if ((result.resetRevision || 0) < resetRevision) return;
      messagesUpdating();
      // Pages never replace a newer streamed snapshot of the same message.
      const present = new Set(messages.map(message => message.id));
      messages = Format.mergeMessages(messages, (result.items || []).filter(message => !present.has(message.id)));
      oldestCursor = result.oldestCursor || "";
      hasOlderMessages = !!result.hasMore && !!oldestCursor && oldestCursor !== cursor;
      messagesLoaded(true);
    }, true);
  }
  function sendMessage() {
    const text = draftText, key = conversation, sendGeneration = generation;
    if (sending || generating || busy || !text.trim()) return false;
    sending = true; lastError = "";
    // Clear synchronously; the sent text returns if the backend refuses it.
    restoringDraft = true; draftText = ""; restoringDraft = false;
    ++draftRevision; flushDraft();
    request("send", {conversation: key, text: text}, (result, error) => {
      if (key !== conversation) return;
      sending = false;
      if (error) {
        lastError = error.message || "Could not send the message.";
        // Restore only into an empty composer; never overwrite a new draft.
        if (!draftText) draftText = text;
        return;
      }
      if (sendGeneration === generation) messageSent();
    }, true);
    return true;
  }
  // Ctrl+Tab steps through the model's levels and wraps around. The change
  // shows at once; a refusal restores the level the backend kept.
  function cycleThinking(delta) {
    const levels = thinkingLevels, key = conversation, before = thinkingLevel;
    const level = levels[(thinkingIndex + delta + levels.length) % levels.length];
    savedThinkingLevel = level; ++thinkingRequests;
    request("setThinking", {conversation: key, level: level}, (result, error) => {
      thinkingRequests = Math.max(0, thinkingRequests - 1);
      if (error && key === conversation && savedThinkingLevel === level) savedThinkingLevel = before;
    });
    return level;
  }
  function stopReply() { if (generating) request("cancel", {conversation: conversation}); }
  function resetConversation() {
    if (busy || sending) return;
    const key = conversation;
    resetting = true;
    request("reset", {conversation: key}, (result, error) => {
      if (key !== conversation) return;
      resetting = false;
      if (!error) applySnapshot(result);
    });
  }
  // Only the local model occupies the GPU.
  function unloadModel() {
    if (!local || busy || sending) return;
    unloadPending = true;
    request("unload", {}, (result, error) => {
      unloadPending = false;
      if (!error && result?.unloaded) modelUnloaded();
    });
  }
  // The result stays staged until Enter accepts the preview. Escape resolves
  // the source callback without edits, including while the model is running.
  function correctText(text, callback, provider = "qwen") {
    const id = "qml-" + Date.now() + "-" + (++correctionSequence);
    correctionCalls[id] = {callback:callback, result:null, decision:""};
    request("correctText", {text:text, conversation:provider, reportId:id, review:true}, (result,error) => {
      const call = correctionCalls[id];
      if (!call) return;
      if (error) { delete correctionCalls[id]; callback(null,error); return; }
      if (result?.cancelled) { resolveCorrection(id,"reject"); return; }
      call.result = result;
      if (call.decision) resolveCorrection(id,call.decision);
    }, true);
    return id;
  }
  function finishCorrection(result, state, message = "") {
    if (result?.reportId) request("finishCorrection", {reportId: result.reportId, status: state, text: message}, null, true);
  }
  function search(query, callback) { request("search", {conversation: conversation, query: query}, callback, true); }
  function flushDraft() {
    draftTimer.stop();
    request("saveDraft", {conversation: conversation, text: draftText}, null, true);
  }
  onDraftTextChanged: {
    if (restoringDraft) return;
    ++draftRevision;
    draftTimer.restart();
  }
  Component.onDestruction: if (draftTimer.running) flushDraft()

  Timer { id: draftTimer; interval: 300; onTriggered: root.flushDraft() }
  Timer { id: restartTimer; interval: 3000; onTriggered: if (root.enabled) backend.running = true }
  Process {
    id: backend
    command: root.command
    running: root.enabled
    stdinEnabled: true
    onStarted: {
      root.revision = -1; root.resetRevision = 0;
      root.generating = false; root.unloading = false;
      root.resetting = false; root.unloadPending = false;
      root.initialize();
    }
    stdout: SplitParser { onRead: data => root.acceptLine(data) }
    onExited: {
      root.generating = false; root.unloading = false; root.sending = false;
      const callbacks = root.pending; root.pending = ({});
      for (const id in callbacks) if (callbacks[id].callback) callbacks[id].callback(null, {message: "The assistant service restarted. Check the conversation before sending again."});
      if (root.enabled) restartTimer.restart();
    }
  }
}
