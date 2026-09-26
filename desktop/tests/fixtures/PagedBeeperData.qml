import QtQuick
import "../../features/messenger"

// An in-memory transport for the real state controller. Never starts Beeper.
BeeperData {
  enabled: false
  state: "connected"
  property var requests: []
  function request(method, params, callback, quiet) {
    if (["accounts", "chats", "unreadCounts", "messages", "message", "search", "send", "read", "unread", "archive", "react", "download"].includes(method))
      requests = requests.concat([{method: method, params: params, callback: callback, quiet: quiet === true}]);
    else if (callback) Qt.callLater(() => callback({}, null));
  }
  function respond(method, result, error) {
    const index = requests.findIndex(request => request.method === method);
    if (index < 0) throw new Error("No pending " + method + " request");
    const request = requests[index];
    requests = requests.filter((_, i) => i !== index);
    request.callback(result, error || null);
  }
}
