import QtQuick
import Quickshell
import Quickshell.Io
import "../../ui/Theme.js" as Theme

// One lazy local worker serves all message views. TeX never goes to a website.
Scope {
  id: root
  property list<string> command: ["quickshell-math"]
  property var entries: ({})
  property var queue: []
  property var current: null
  property bool ready: false
  property int sequence: 0
  property int revision: 0
  property int cacheBytes: 0
  property int cacheCount: 0

  function lookup(encoded, display) {
    const key = display + ":" + encoded;
    if (entries[key]) return entries[key];
    if (cacheCount >= 256 || cacheBytes >= 16 * 1024 * 1024 || encoded.length > 8192) return null;
    entries[key] = {pending: true}; ++cacheCount;
    queue.push({id: ++sequence, key: key, encoded: encoded, display: display === "1", color: Theme.foreground});
    Qt.callLater(pump);
    return null;
  }
  function pump() {
    if (current) return;
    if (!queue.length) { idle.restart(); return; }
    idle.stop();
    if (!worker.running) { worker.running = true; return; }
    if (!ready) return;
    current = queue.shift();
    watchdog.restart();
    worker.write(JSON.stringify(current) + "\n");
  }
  function accept(line) {
    let result;
    try { result = JSON.parse(line); } catch (_) { return; }
    if (!current || result.id !== current.id) return;
    watchdog.stop();
    if (!result.svg?.startsWith("data:image/svg+xml;base64,") || !(result.width > 0 && result.width <= 4000 && result.height > 0 && result.height <= 2000)) result = {error: true};
    entries[current.key] = result;
    cacheBytes += result.svg?.length || 0;
    current = null; ++revision;
    Qt.callLater(pump);
  }
  function render(html, scale) {
    return String(html).replace(/<span data-math="([A-Za-z0-9+/=]+)" data-display="([01])">([\s\S]*?)<\/span>/g, (match, encoded, display) => {
      const result = lookup(encoded, display);
      if (!result?.svg) return match;
      const image = '<img data-math-source="' + encoded + '" data-display="' + display + '" src="' + result.svg
        + '" width="' + Math.max(1, Math.round(result.width * scale)) + '" height="' + Math.max(1, Math.round(result.height * scale)) + '" style="vertical-align:middle" />';
      return display === "1" ? "<br/>" + image + "<br/>" : image;
    }).replace(/<p><br\/>/g, "<p>").replace(/<br\/><\/p>/g, "</p>");
  }
  Timer { id: watchdog; interval: 5000; onTriggered: worker.running = false }
  Timer { id: idle; interval: 60000; onTriggered: if (!root.current && !root.queue.length) worker.running = false }
  Process {
    id: worker
    command: root.command
    stdinEnabled: true
    onStarted: { root.ready = true; root.pump(); }
    stdout: SplitParser { onRead: data => root.accept(data) }
    onExited: {
      root.ready = false; watchdog.stop();
      if (root.current) root.entries[root.current.key] = {error: true};
      for (const request of root.queue) root.entries[request.key] = {error: true};
      root.current = null; root.queue = []; ++root.revision;
    }
  }
}
