import QtQuick
import Quickshell
import "./BeeperFormat.js" as Format

// Resolve incomplete API previews without delaying the conversation list or
// replacing its original preview ID (also used by read receipts).
Scope {
  id: root
  required property var beeperData
  property bool active: beeperData.enabled && beeperData.connected && !beeperData.demo
  readonly property var chats: beeperData.chats
  property var entries: ({})
  property var queue: []
  property bool busy: false
  property int generation: 0
  property int serial: 0

  function invalidate(chatID) {
    const copy = Object.assign({}, entries);
    delete copy[JSON.stringify(chatID)];
    entries = copy;
    Qt.callLater(schedule);
  }

  function schedule() {
    if (!active) return;
    const next = {}, pending = [];
    for (const chat of chats) {
      if (!chat.preview?.id || Format.activityBody(chat.preview)) continue;
      const id = JSON.stringify(chat.id), key = Format.previewKey(chat), previous = entries[id];
      if (previous?.key === key && (previous.pending || Date.now() - previous.updated < (previous.failed ? 5000 : 60000))) {
        next[id] = previous;
        continue;
      }
      next[id] = {key: key, pending: true, version: ++serial};
      pending.push({chatID: chat.id, key: key, version: serial});
    }
    entries = next;
    queue = queue.filter(job => entries[JSON.stringify(job.chatID)]?.version === job.version).concat(pending);
    processNext();
  }
  function processNext() {
    if (!active || busy || !queue.length) return;
    const job = queue[0], id = JSON.stringify(job.chatID), requestGeneration = generation;
    queue = queue.slice(1); busy = true;
    let pages = 0, lookups = 0;
    const cursors = [], messagesByID = Object.create(null);
    function valid() { return active && requestGeneration === generation && entries[id]?.version === job.version; }
    function finish(message, failed = false) {
      if (requestGeneration !== generation) return;
      if (valid()) entries = Object.assign({}, entries, {[id]: {key: job.key, message: message, pending: false, failed: failed, updated: Date.now()}});
      busy = false; Qt.callLater(processNext);
    }
    function scan(items, index, page) {
      if (!valid()) { finish(null); return; }
      if (index >= items.length) {
        if (page.hasMore && page.oldestCursor && pages < 3 && !cursors.includes(page.oldestCursor)) load(page.oldestCursor);
        else finish(null);
        return;
      }
      const message = items[index];
      if (message.isDeleted) { scan(items, index + 1, page); return; }
      if (Format.activityBody(message)) { finish(message); return; }
      if (message.type !== "REACTION" || message.isSender || !message.linkedMessageID || !message.senderID) {
        scan(items, index + 1, page); return;
      }
      function acceptReaction(parent) {
        if (!valid()) { finish(null); return; }
        // Removed reactions disappear from the target's reaction list. Never
        // attribute another participant's emoji, or a reaction to someone else.
        const reactions = parent?.isSender && !parent.isDeleted
          ? (parent.reactions || []).filter(value => value.participantID === message.senderID && value.reactionKey) : [];
        const reaction = reactions.find(value => value.id === message.id) || (reactions.length === 1 ? reactions[0] : null);
        if (reactions.length) finish(Object.assign({}, message, {previewReaction: reaction?.reactionKey || true}));
        else scan(items, index + 1, page);
      }
      const parent = messagesByID[message.linkedMessageID];
      if (parent) { acceptReaction(parent); return; }
      if (++lookups > 8) { scan(items, index + 1, page); return; }
      beeperData.request("message", {chatID: job.chatID, messageID: message.linkedMessageID}, (result, error) => {
        if (error) { finish(null, true); return; }
        messagesByID[message.linkedMessageID] = result;
        acceptReaction(result);
      }, true);
    }
    function load(cursor = "") {
      if (!valid()) { finish(null); return; }
      ++pages; cursors.push(cursor);
      const params = {chatID: job.chatID};
      if (cursor) { params.cursor = cursor; params.direction = "before"; }
      beeperData.request("messages", params, (result, error) => {
        if (!valid()) { finish(null); return; }
        if (error || !result) { finish(null, true); return; }
        // Unlike the conversation history, this scan retains hidden reactions.
        const items = (result.items || []).slice().sort((a, b) => new Date(b.timestamp || 0) - new Date(a.timestamp || 0));
        for (const message of items) messagesByID[message.id] = message;
        scan(items, 0, result);
      }, true);
    }
    load();
  }
  onChatsChanged: Qt.callLater(schedule)
  onActiveChanged: {
    ++generation; busy = false; queue = []; entries = ({});
    if (active) Qt.callLater(schedule);
  }
  Component.onCompleted: Qt.callLater(schedule)
}
