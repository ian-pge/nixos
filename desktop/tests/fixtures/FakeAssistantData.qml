import QtQuick
import "../../features/assistant"

// In-memory transport for the real assistant model. Never starts Ollama.
AssistantData {
  enabled: false
  property var requests: []
  function request(method, params, callback, quiet) {
    requests = requests.concat([{method: method, params: params, callback: callback, quiet: quiet === true}]);
  }
  function pending(method) { return requests.filter(request => request.method === method); }
  function respond(method, result, error) {
    const index = requests.findIndex(request => request.method === method);
    if (index < 0) throw new Error("No pending " + method + " request");
    const request = requests[index];
    requests = requests.filter((_, i) => i !== index);
    if (request.callback) request.callback(result, error || null);
  }
  function message(id, role, text, extra) {
    return Object.assign({id: id, role: role, isSender: role === "user", text: text,
      html: "<p>" + text + "</p>", state: role === "assistant" ? "complete" : "",
      timestamp: "2026-11-12T10:00:00Z"}, extra || {});
  }
}
