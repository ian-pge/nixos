import QtQuick
import "../../features/messenger"

// An in-memory transport for the real state controller. Never starts Beeper.
BeeperData {
  enabled: false
  state: "connected"
  // Most interaction tests control replies directly. Navigation performance
  // tests opt into the production delay explicitly.
  navigationLoadDelay: 0
  property var requests: []
  property bool deferDrafts: false
  property bool deferRecording: false
  property bool deferAttachments: false
  function request(method, params, callback, quiet) {
    if (["accounts", "chats", "unreadCounts", "messages", "message", "search", "send", "read", "unread", "updateChat", "react", "download", "saveAttachment"].includes(method)
        || (deferDrafts && ["getDraft", "saveDraft"].includes(method))
        || (deferAttachments && method === "stageAttachment")
        || (deferRecording && ["prepareRecording", "discardAttachment"].includes(method)))
      requests = requests.concat([{method: method, params: params, callback: callback, quiet: quiet === true}]);
    else if (callback) Qt.callLater(() => callback({}, null));
  }
  function respond(method, result, error) {
    const index = requests.findIndex(request => request.method === method);
    if (index < 0) throw new Error("No pending " + method + " request");
    const request = requests[index];
    requests = requests.filter((_, i) => i !== index);
    if (request.callback) request.callback(result, error || null);
  }
}
