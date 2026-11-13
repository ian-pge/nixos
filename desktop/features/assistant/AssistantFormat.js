.pragma library
.import "../../ui/TextSearch.js" as TextSearch

// Message HTML comes from the backend: Goldmark output for replies and escaped
// text for the user's messages. Search is shared with the messenger.
function highlightHTML(html, query, background, foreground) { return TextSearch.highlightHTML(html, query, background, foreground); }
// Web and mail links only, in reading order; the first one opens with l.
function links(html) {
  const result = [];
  const pattern = /<a href="([^"]+)">/g;
  let match;
  while ((match = pattern.exec(String(html || "")))) {
    const url = match[1].replace(/&amp;/g, "&");
    if (/^(https?:\/\/|mailto:)/i.test(url) && !result.includes(url)) result.push(url);
  }
  return result;
}
function time(value) {
  if (!value) return "";
  const date = new Date(value);
  return isNaN(date.getTime()) ? "" : Qt.formatDateTime(date, "HH:mm");
}
function dateLabel(value) {
  if (!value) return "";
  const date = new Date(value);
  return isNaN(date.getTime()) ? "" : date.toLocaleDateString(Qt.locale("en_GB"), "dddd d MMMM");
}
function shouldSend(key, modifiers, composing) {
  return !composing && (key === Qt.Key_Return || key === Qt.Key_Enter) && !(modifiers & Qt.ShiftModifier);
}
// Replace changed rows by identity and keep chronological order. A user
// message and its reply can share a millisecond: ties keep arrival order.
function mergeMessages(before, after) {
  const unique = {}, order = [];
  before.concat(after).forEach(message => { if (!message?.id) return; if (!unique[message.id]) order.push(message.id); unique[message.id] = message; });
  return order.map((id, index) => ({message: unique[id], order: index}))
    .sort((a, b) => (new Date(a.message.timestamp || 0) - new Date(b.message.timestamp || 0)) || a.order - b.order)
    .map(row => row.message);
}

// Thinking levels run from green (lowest) to red (highest) through yellow and
// peach; a two-level model uses only the ends.
var thinkingStops = ["#a6da95", "#eed49f", "#f5a97f", "#ed8796"];
function thinkingColor(index, count) {
  if (count < 2 || index < 0) return thinkingStops[0];
  const position = Math.min(1, index / (count - 1)) * (thinkingStops.length - 1);
  return thinkingStops[Math.round(position)];
}
var thinkingNames = {off: "Off", high: "High", low: "Low", medium: "Medium", xhigh: "Extra high"};
function thinkingName(level, levels) {
  if (levels && levels.length === 2 && levels[0] === "off") return level === "off" ? "Off" : "On";
  return thinkingNames[level] || level;
}
