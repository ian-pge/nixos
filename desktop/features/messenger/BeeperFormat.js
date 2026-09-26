.pragma library

function chatTitle(chat) { return chat ? String(chat.title || chat.name || "Conversation") : "Messages"; }
function isChatUnread(chat) { return !!chat && (chat.unreadCount > 0 || chat.isMarkedUnread === true); }
function orderChats(chats, unreadFirst) {
  // Stable partition of the view only: keep Beeper's order within each group
  // and leave its source list intact for the return to normal ordering.
  return unreadFirst ? chats.filter(isChatUnread).concat(chats.filter(chat => !isChatUnread(chat))) : chats;
}
// Beeper can report a manual unread marker together with archive state. Keep
// that explicit reminder in our inbox without rewriting the server's archive flag.
function isChatInInbox(chat) { return !!chat && (!chat.isArchived || chat.isMarkedUnread === true); }
function isChatInView(chat, archivedOnly) { return archivedOnly ? chat?.isArchived === true : isChatInInbox(chat); }
function chatSubtitle(chat) {
  if (!chat) return "All your conversations, in one place";
  let subtitle = "";
  if (chat.type === "group") {
    const participants = chat.participants;
    const count = typeof participants?.total === "number" && isFinite(participants.total) && participants.total >= 0
      ? participants.total : participants?.hasMore === false && Array.isArray(participants.items) ? participants.items.length : null;
    subtitle = count === null ? "Group conversation" : count + (count === 1 ? " member" : " members");
  }
  return subtitle + (chat.isMuted ? (subtitle ? "  ·  " : "") + "Muted" : "");
}
function chatAvatarSource(chat) {
  let source = chat?.imgURL || "";
  if (!source && chat?.type === "single") {
    const contact = (chat.participants?.items || []).find(participant => participant.isSelf === false && participant.imgURL);
    source = contact?.imgURL || "";
  }
  return source.startsWith("/") ? "file://" + source : source;
}
function initials(title) { return String(title || "?").trim().split(/\s+/).slice(0, 2).map(s => s.charAt(0)).join("").toUpperCase(); }
function stableHash(value) {
  const text = String(value || "");
  let hash = 2166136261;
  for (let i = 0; i < text.length; ++i) hash = Math.imul(hash ^ text.charCodeAt(i), 16777619) >>> 0;
  return hash;
}
function networkBadge(network) {
  const name = String(network || "").trim();
  const key = name.toLowerCase().replace(/[\s_-]/g, "");
  // Brand glyphs from the installed Nerd Font; no remote icon downloads.
  if (key === "all") return {key: "all", name: "All", glyph: "\uf086", logo: true};
  if (key.startsWith("whatsapp")) return {key: "whatsapp", name: "WhatsApp", glyph: "\uf232", logo: true};
  if (key.startsWith("telegram")) return {key: "telegram", name: "Telegram", glyph: "\ue217", logo: true};
  if (key.startsWith("instagram")) return {key: "instagram", name: "Instagram", glyph: "\uf16d", logo: true};
  if (key === "sms" || key === "sms/rcs" || key === "rcs" || key === "androidsms" || key.startsWith("googlemessages"))
    return {key: "sms", name: "SMS", glyph: "\uf27a", logo: true};
  if (key === "signal") return {key: "signal", name: "Signal", glyph: "S", logo: false};
  return {key: "other", name: name, glyph: Array.from(name)[0]?.toUpperCase() || "", logo: false};
}
function quickReactions(chat) {
  return networkBadge(chat?.network).key === "telegram"
    ? ["🤣", "❤️", "🔥", "💯", "🤡"] : ["😂", "💜", "🔥", "💯", "🤡"];
}
function accountConnectionIssues(accounts, chats) {
  const issues = {};
  const labels = {
    connecting: "Connecting…", connection_required: "Connection required",
    reconnect_required: "Reconnection required", attention_required: "Connection needs attention",
    disconnected: "Disconnected", disabled: "Account disabled"
  };
  for (const account of accounts || []) {
    const id = account.accountID || account.id;
    const message = labels[account.status];
    // Backfilling is a connected account importing history. An absent or new
    // status is not evidence of a failure on older/newer API versions.
    if (!id || typeof message !== "string") continue;
    const chat = (chats || []).find(chat => chat.accountID === id);
    const network = networkBadge(account.network || chat?.network || account.bridge?.type);
    issues[id] = {network: network.key, name: network.name || "Account", message: message};
  }
  return issues;
}
function serviceConnectionIssue(state) {
  return ({
    "loading-token": "Connecting to Beeper…", connecting: "Reconnecting to Beeper…",
    offline: "Beeper is offline", "needs-token": "Connect to Beeper",
    "invalid-token": "Beeper connection needs attention", "keyring-unavailable": "Unlock the keyring to reconnect to Beeper"
  })[state] || "";
}
function networkConnectionIssue(network, issues, serviceIssue) {
  if (serviceIssue) return serviceIssue;
  const messages = Object.values(issues || {}).filter(issue => network === "all" || issue.network === network)
    .map(issue => (network === "all" ? issue.name + ": " : "") + issue.message);
  return Array.from(new Set(messages)).join("\n");
}
function chatConnectionIssue(chat, issues, serviceIssue) {
  if (!chat) return "";
  if (serviceIssue) return serviceIssue;
  if (chat.accountID) return issues?.[chat.accountID]?.message || "";
  return networkConnectionIssue(networkBadge(chat.network).key, issues, "");
}
function senderKey(message) {
  return message?.senderID || (message?.isSender ? "self" : "name:" + (message?.senderName || "Contact"));
}
function selfParticipantIDs(chat, accounts) {
  const ids = (chat?.participants?.items || []).filter(person => person.isSelf === true).map(person => person.id);
  const account = (accounts || []).find(account => (account.id || account.accountID) === chat?.accountID);
  if (account?.user?.id) ids.push(account.user.id);
  return Array.from(new Set(ids.filter(Boolean)));
}
function ownReactionKeys(message, selfIDs) {
  return Array.from(new Set((message?.reactions || [])
    .filter(reaction => selfIDs.includes(reaction.participantID))
    .map(reaction => reaction.reactionKey).filter(Boolean)));
}
function withOwnReactions(message, selfIDs, keys) {
  if (!selfIDs.length) return message;
  const reactions = message.reactions || [];
  const others = reactions.filter(reaction => !selfIDs.includes(reaction.participantID));
  return Object.assign({}, message, {reactions: others.concat(keys.map(key =>
    reactions.find(reaction => selfIDs.includes(reaction.participantID) && reaction.reactionKey === key)
      || {participantID: selfIDs[0], reactionKey: key, emoji: true}))});
}
function senderProfile(message, chat, accounts) {
  const people = chat?.participants?.items || [];
  const account = (accounts || []).find(account => (account.id || account.accountID) === (message.accountID || chat?.accountID));
  const person = (message.senderID ? people.find(person => person.id === message.senderID) : null)
    || (message.isSender ? people.find(person => person.isSelf === true) || account?.user : null);
  return {
    id: senderKey(message),
    title: message.isSender ? "You" : message.senderName || person?.fullName || person?.displayName || "Contact",
    imgURL: person?.imgURL || (!message.isSender && chat?.type === "single" ? chat.imgURL || "" : "")
  };
}
function participantProfile(id, chat, accounts, accountID) {
  const person = (chat?.participants?.items || []).find(person => person.id === id);
  const account = (accounts || []).find(account => (account.id || account.accountID) === (accountID || chat?.accountID));
  const isSelf = person?.isSelf === true || (!!id && id === account?.user?.id);
  const user = isSelf ? person || account?.user : person;
  return {
    id: id || "unknown-participant", isSelf: isSelf, anonymous: !id,
    title: isSelf ? "You" : user?.fullName || user?.displayName || user?.username || user?.phoneNumber || id || "?",
    // Only a known peer in a private chat may use that conversation's photo.
    // Never put the group's or sender's picture on an unidentified reactor.
    imgURL: user?.imgURL || (isSelf ? account?.user?.imgURL || "" : person && chat?.type === "single" ? chat.imgURL || "" : "")
  };
}
function messageReactions(message, chat, accounts) {
  const seen = new Set(), reactions = [];
  for (const reaction of message?.reactions || []) {
    const key = reaction.reactionKey || (typeof reaction.emoji === "string" ? reaction.emoji : "") || "♡";
    const participantID = reaction.participantID || "";
    const identity = JSON.stringify([participantID, key]);
    if (participantID && seen.has(identity)) continue;
    seen.add(identity);
    reactions.push({key: key, imgURL: reaction.imgURL || "",
      person: participantProfile(participantID, chat, accounts, message?.accountID),
      // Older aggregate-only data cannot identify the people behind its count.
      count: participantID ? 1 : Math.max(1, Number(reaction.count) || 1)});
  }
  return reactions;
}
function hasReadReceipt(value) {
  return value === true || (typeof value === "string" && value !== "" && !isNaN(Date.parse(value)));
}
function messageReaders(message, chat, accounts) {
  // Public API `seen`: boolean, ISO timestamp, or participant ID -> either.
  // Delivery success and our own unread marker do not identify any readers.
  const seen = message?.seen;
  const people = chat?.participants?.items || [];
  if (seen && typeof seen === "object" && !Array.isArray(seen)) {
    const readers = [];
    for (const id of Object.keys(seen)) {
      if (!hasReadReceipt(seen[id]) || id === message.senderID) continue;
      const person = participantProfile(id, chat, accounts, message?.accountID);
      if (!person.isSelf) readers.push(person);
    }
    return readers;
  }
  if (!hasReadReceipt(seen) || !message.isSender) return [];
  if (chat?.type === "single") {
    const contact = people.find(person => person.isSelf === false
      && !participantProfile(person.id, chat, accounts, message?.accountID).isSelf);
    if (contact) return [participantProfile(contact.id, chat, accounts, message?.accountID)];
    if (chat.title || chat.name) return [{id: "contact:" + (chat.id || ""),
      title: chat.title || chat.name, imgURL: chat.imgURL || "", isSelf: false, anonymous: false}];
  }
  return [{id: "unidentified-reader", title: "?", imgURL: "", isSelf: false, anonymous: true}];
}
function readersLabel(readers) {
  return !readers?.length ? "" : readers[0].anonymous ? "Read" : "Read by " + readers.map(person => person.title).join(", ");
}
function readReceiptLabel(message, chat, accounts) { return readersLabel(messageReaders(message, chat, accounts)); }
function readReceiptReaders(messages, chat, accounts) {
  const readers = {};
  const account = (accounts || []).find(account => (account.id || account.accountID) === chat?.accountID);
  const cumulative = chat?.type === "single" && networkBadge(chat.network || account?.network).key === "telegram";
  let latestReadTime = -Infinity, latestReaders = [];
  function sent(message) {
    const status = message.sendStatus?.status || "";
    return message.isSender && status !== "PENDING" && !status.startsWith("FAIL");
  }
  function sentTime(message) { return message.timestamp ? new Date(message.timestamp).getTime() : NaN; }
  for (const message of messages) {
    const people = messageReaders(message, chat, accounts);
    readers[message.id] = people;
    const timestamp = sentTime(message);
    if (cumulative && sent(message) && people.length && timestamp > latestReadTime) {
      latestReadTime = timestamp; latestReaders = people;
    }
  }
  // Telegram private-chat receipts mark history read through a message. Beeper
  // attaches the peer to that one message, not each earlier outgoing message.
  // Do not infer group readers, later messages, equal-time ordering, or delivery.
  if (latestReaders.length) {
    for (const message of messages) {
      if (sent(message) && !readers[message.id].length && sentTime(message) < latestReadTime)
        readers[message.id] = latestReaders;
    }
  }
  return readers;
}
function readReceiptLabels(messages, chat, accounts) {
  const readers = readReceiptReaders(messages, chat, accounts), labels = {};
  for (const id of Object.keys(readers)) labels[id] = readersLabel(readers[id]);
  return labels;
}
function assignSenderColors(previous, identities, palette) {
  const colors = Object.assign({}, previous);
  const used = new Set(Object.values(colors));
  for (const identity of Array.from(new Set(identities)).sort()) {
    if (Object.prototype.hasOwnProperty.call(colors, identity)) continue;
    const hash = stableHash(identity);
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
function escapeTextMarkup(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}
function searchTextRanges(text, query) {
  // Keep original UTF-16 offsets while folding case/accents, including emoji
  // and decomposed accents. The API query itself is left completely unchanged.
  function fold(value) { return value.normalize("NFD").toLowerCase().replace(/[\u0300-\u036f]/g, ""); }
  const words = [...new Set(String(query || "").trim().split(/\s+/).map(fold).filter(Boolean))];
  if (!words.length || !text) return [];
  let normalized = "", offset = 0;
  const positions = [];
  for (const character of Array.from(text)) {
    const value = fold(character), end = offset + character.length;
    for (let i = 0; i < value.length; ++i) positions.push({start: offset, end: end});
    if (!value && positions.length) positions[positions.length - 1].end = end;
    normalized += value; offset = end;
  }
  const ranges = [];
  for (const word of words) {
    let start = normalized.indexOf(word);
    while (start >= 0) {
      ranges.push({start: positions[start].start, end: positions[start + word.length - 1].end});
      start = normalized.indexOf(word, start + 1);
    }
  }
  ranges.sort((a, b) => a.start - b.start || b.end - a.end);
  const merged = [];
  for (const range of ranges) {
    const last = merged[merged.length - 1];
    if (last && range.start <= last.end) last.end = Math.max(last.end, range.end);
    else merged.push({start: range.start, end: range.end});
  }
  return merged;
}
function highlightText(text, query, background, foreground) {
  const ranges = searchTextRanges(text, query);
  if (!ranges.length) return "";
  let html = "", start = 0;
  for (const range of ranges) {
    html += escapeTextMarkup(text.slice(start, range.start))
      + '<span style="background-color:' + background + ';color:' + foreground + '">'
      + escapeTextMarkup(text.slice(range.start, range.end)) + '</span>';
    start = range.end;
  }
  // Only our spans become markup: message content can never create links,
  // images or external resource loads. Preserve whitespace and line breaks.
  return '<p style="white-space:pre-wrap;line-height:120%;margin-top:0;margin-bottom:0;margin-left:0;margin-right:0">'
    + (html + escapeTextMarkup(text.slice(start))).replace(/\n/g, '<br/>') + '</p>';
}
function quotePreview(message) {
  const body = text(message).trim();
  if (body) return body;
  const attachment = message?.attachments?.[0];
  if (!attachment) return "Message";
  if (attachment.isSticker) return "Sticker";
  const kind = attachmentType(attachment);
  if (kind === "audio") return attachment.isVoiceNote || String(attachment.type || "").startsWith("voice") ? "Voice message" : "Audio";
  return ({image: "Photo", gif: "GIF", video: "Video"})[kind]
    || attachment.fileName || "Attachment";
}
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
  if (value && value.attachments && value.attachments.length) return "Attachment";
  return "Open conversation";
}
function time(value) {
  if (!value) return "";
  const date = new Date(typeof value === "number" && value < 100000000000 ? value * 1000 : value);
  return isNaN(date.getTime()) ? "" : Qt.formatDateTime(date, "HH:mm");
}
function dateLabel(value) {
  if (!value) return "";
  const date = new Date(value);
  return isNaN(date.getTime()) ? "" : date.toLocaleDateString(Qt.locale("en_GB"), "dddd d MMMM");
}
function duration(milliseconds) {
  const seconds = Math.floor(Math.max(0, milliseconds) / 1000);
  return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + seconds % 60;
}
function bytes(value) {
  if (!value) return "";
  return value > 1048576 ? (value / 1048576).toFixed(1) + " MiB" : Math.ceil(value / 1024) + " KiB";
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
  if (capability === false || typeof capability === "number" && capability <= 0) return false;
  const maxAge = chat.capabilities ? chat.capabilities[operation + "MaxAge"] : 0;
  if (message && maxAge > 0 && Date.now() - new Date(message.timestamp) > maxAge * 1000) return false;
  return true;
}
function links(message) {
  return (message?.links || []).filter(link => /^(https?:|mailto:)/i.test(link.url || ""));
}
