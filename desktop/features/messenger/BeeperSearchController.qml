import QtQuick
import Quickshell
import "./BeeperFormat.js" as Format

// Search has its own pages and generation; it never replaces the chat history.
Scope {
  id: root
  objectName: "beeperSearchController"
  required property var beeperData
  property bool opened: false
  property string query: ""
  property var results: []
  property int index: -1
  property bool loading: false
  property bool hasMore: false
  property string cursor: ""
  property string errorText: ""
  property bool failedPage: false
  property int generation: 0
  property bool navigateWhenReady: false
  property int pendingIndex: -1
  property var usedCursors: ({})
  readonly property string chatID: beeperData.currentChatID
  readonly property var currentMatch: results[index] || null
  readonly property string counter: errorText ? "" : loading ? (results.length ? "Loading matches…" : "Searching…")
    : !query.trim() ? "" : !results.length ? (debounce.running ? "Searching…" : "No matches")
    : (index >= 0 ? (index + 1) + " / " : "") + results.length + (hasMore ? "+" : "") + (index < 0 ? " matches" : "")
  signal matchRequested(var message)
  signal invalidated()

  function reset() {
    invalidated();
    ++generation; debounce.stop(); loading = false; results = []; index = -1;
    cursor = ""; hasMore = false; errorText = ""; failedPage = false; usedCursors = ({});
    navigateWhenReady = false; pendingIndex = -1;
  }
  function close() { opened = false; query = ""; reset(); }
  onChatIDChanged: close()
  onOpenedChanged: if (!opened) reset()
  onQueryChanged: {
    reset();
    if (opened && chatID && query.trim()) debounce.restart();
  }
  function search(older = false) {
    if (!opened || !chatID || !query.trim() || loading || (older && !hasMore)) return;
    debounce.stop();
    const token = generation, targetChat = chatID, text = query.trim(), page = older ? cursor : "";
    loading = true; errorText = "";
    beeperData.request("search", {chatID: targetChat, query: text, cursor: page, direction: "before"}, (result, error) => {
      if (token !== generation || !opened || chatID !== targetChat) return;
      loading = false;
      if (error || !result) {
        failedPage = older;
        errorText = "Search unavailable. Press Enter to retry.";
        navigateWhenReady = false; pendingIndex = -1; return;
      }
      failedPage = false;
      const selectedID = currentMatch?.id;
      const rows = (result.items || []).filter(message => message.id && message.chatID === targetChat
        && !message.isDeleted && !message.isHidden && !beeperData.deletedMessageIDs?.[targetChat]?.[message.id]);
      results = Format.mergeMessages(older ? results : [], rows).reverse();
      index = selectedID ? results.findIndex(message => message.id === selectedID) : -1;
      if (page) usedCursors = Object.assign({}, usedCursors, {[page]: true});
      cursor = result.oldestCursor || "";
      hasMore = !!result.hasMore && !!cursor && !usedCursors[cursor];
      if (navigateWhenReady) {
        if (pendingIndex < results.length) {
          const next = Math.max(0, pendingIndex);
          navigateWhenReady = false; pendingIndex = -1; select(next);
        } else if (hasMore) Qt.callLater(() => { if (token === generation) search(true); });
        else { navigateWhenReady = false; pendingIndex = -1; }
      }
    }, true);
  }
  function select(next) {
    if (next < 0 || next >= results.length) return;
    index = next; errorText = ""; matchRequested(results[index]);
  }
  function accept() {
    if (!query.trim()) return;
    if (errorText && failedPage && !loading) {
      navigateWhenReady = true; pendingIndex = results.length; search(true); return;
    }
    if (currentMatch && !debounce.running && !loading) { select(index); return; }
    navigateWhenReady = true; pendingIndex = 0;
    if (results.length && !debounce.running && !loading) { navigateWhenReady = false; pendingIndex = -1; select(0); }
    else if (!loading) search(hasMore && !!cursor);
  }
  function move(delta) {
    if (!opened || !query.trim() || loading) return;
    if (!results.length || debounce.running) { accept(); return; }
    const next = index < 0 ? 0 : index + delta;
    if (next >= results.length && hasMore) {
      navigateWhenReady = true; pendingIndex = results.length; search(true);
    } else if (next < 0 && hasMore) select(0);
    else select((next + results.length) % results.length);
  }
  Timer { id: debounce; interval: 250; onTriggered: root.search() }
}
