.pragma library

function chatTitle(chat) { return chat ? String(chat.title || chat.name || "Conversation") : "Messages"; }
function chatAvatarSource(chat) {
  let source = chat?.imgURL || "";
  if (!source && chat?.type === "single") {
    const contact = (chat.participants?.items || []).find(participant => participant.isSelf === false && participant.imgURL);
    source = contact?.imgURL || "";
  }
  return source.startsWith("/") ? "file://" + source : source;
}
function initials(title) { return String(title || "?").trim().split(/\s+/).slice(0, 2).map(s => s.charAt(0)).join("").toUpperCase(); }
function senderKey(message) {
  return message?.senderID || (message?.isSender ? "self" : "name:" + (message?.senderName || "Contact"));
}
function assignSenderColors(previous, identities, palette) {
  const colors = Object.assign({}, previous);
  const used = new Set(Object.values(colors));
  for (const identity of Array.from(new Set(identities)).sort()) {
    if (Object.prototype.hasOwnProperty.call(colors, identity)) continue;
    let hash = 2166136261;
    for (let i = 0; i < identity.length; ++i) hash = Math.imul(hash ^ identity.charCodeAt(i), 16777619) >>> 0;
    let color = "";
    for (let offset = 0; offset < palette.length; ++offset) {
      const candidate = palette[(hash + offset) % palette.length];
      if (!used.has(candidate)) { color = candidate; break; }
    }
    // Larger groups keep distinct pastel values after the named palette is used.
    let step = Object.keys(colors).length;
    while (!color || used.has(color)) {
      color = Qt.hsla((hash / 4294967296 + step++ * 0.61803398875) % 1, 0.55, 0.76, 1).toString();
    }
    colors[identity] = color;
    used.add(color);
  }
  return colors;
}
function text(message) { return message ? String(message.plainText !== undefined ? message.plainText : message.text || "") : ""; }
function attachmentType(attachment) {
  const type = String(attachment.type || "").toLowerCase();
  const mime = String(attachment.mimeType || attachment.mime || "").toLowerCase();
  if (attachment.isVoiceNote || type === "voice-note" || type === "voicenote" || type === "voice_note" || type === "audio" || mime.startsWith("audio/")) return "audio";
  if (type === "video" || mime.startsWith("video/")) return "video";
  if (attachment.isGif || type === "gif" || mime === "image/gif") return "gif";
  if (attachment.isSticker || type === "img" || type === "image" || type === "sticker" || mime.startsWith("image/")) return "image";
  return "file";
}
function attachmentSource(attachment) {
  const source = attachment.srcURL || attachment.url || attachment.path || attachment.id || "";
  return source.startsWith("/") ? "file://" + source : source;
}
function preview(chat) {
  const value = chat ? chat.preview : "";
  if (typeof value === "string") return value;
  if (value && value.plainText !== undefined) return value.plainText;
  if (value && value.text) return value.text;
  if (value && value.attachments && value.attachments.length) return "Pièce jointe";
  return "Ouvrir la conversation";
}
function time(value) {
  if (!value) return "";
  const date = new Date(typeof value === "number" && value < 100000000000 ? value * 1000 : value);
  return isNaN(date.getTime()) ? "" : Qt.formatDateTime(date, "HH:mm");
}
function dateLabel(value) {
  if (!value) return "";
  const date = new Date(value);
  return isNaN(date.getTime()) ? "" : date.toLocaleDateString(Qt.locale("fr_FR"), "dddd d MMMM");
}
function duration(milliseconds) {
  const seconds = Math.floor(Math.max(0, milliseconds) / 1000);
  return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + seconds % 60;
}
function bytes(value) {
  if (!value) return "";
  return value > 1048576 ? (value / 1048576).toFixed(1) + " Mo" : Math.ceil(value / 1024) + " Ko";
}
function mergeMessages(before, after) {
  const unique = {}, order = [];
  before.concat(after).forEach(message => { if (!message.id) return; if (!unique[message.id]) order.push(message.id); unique[message.id] = message; });
  return order.map((id, index) => ({message: unique[id], order: index})).filter(row => !row.message.isDeleted && !row.message.isHidden).sort((a, b) => (new Date(a.message.timestamp || 0) - new Date(b.message.timestamp || 0)) || a.order - b.order).map(row => row.message);
}
function shouldSend(key, modifiers, composing) {
  return !composing && (key === Qt.Key_Return || key === Qt.Key_Enter) && !(modifiers & Qt.ShiftModifier);
}
function supports(chat, operation, message) {
  if (!chat || chat.isReadOnly) return false;
  const capability = chat.capabilities ? chat.capabilities[operation] : undefined;
  if (typeof capability === "number" && capability <= 0) return false;
  const maxAge = chat.capabilities ? chat.capabilities[operation + "MaxAge"] : 0;
  if (message && maxAge > 0 && Date.now() - new Date(message.timestamp) > maxAge * 1000) return false;
  return true;
}
function links(message) {
  return (message?.links || []).filter(link => /^(https?:|mailto:)/i.test(link.url || ""));
}
