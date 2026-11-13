.pragma library

// Search and highlighting shared by the messenger and the assistant chat.
// Matching ignores case and accents and keeps the original UTF-16 offsets,
// including emoji and decomposed accents. Only our spans become markup:
// message content can never create links, images or resource loads.
function escapeTextMarkup(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}
function searchTextRanges(text, query) {
  function fold(value) { return value.normalize("NFD").toLowerCase().replace(/[̀-ͯ]/g, ""); }
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
// Escaped plain text with the matches wrapped in colored spans.
function highlightPlain(text, ranges, background, foreground) {
  let html = "", start = 0;
  for (const range of ranges) {
    html += escapeTextMarkup(text.slice(start, range.start))
      + '<span style="background-color:' + background + ';color:' + foreground + '">'
      + escapeTextMarkup(text.slice(range.start, range.end)) + '</span>';
    start = range.end;
  }
  return html + escapeTextMarkup(text.slice(start));
}
// Trusted HTML (backend Markdown or escaped text): highlight text nodes only,
// never tags or attributes, so the layout stays identical.
function highlightHTML(html, query, background, foreground) {
  if (!String(query || "").trim()) return html;
  const entities = {amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " "};
  return String(html).split(/(<[^>]*>)/g).map(part => {
    if (part.startsWith("<")) return part;
    const text = part.replace(/&(#x[0-9a-f]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp);/gi, (match, key) => {
      if (key[0] !== "#") return entities[key.toLowerCase()] || match;
      const number = parseInt(key.slice(/^#x/i.test(key) ? 2 : 1), /^#x/i.test(key) ? 16 : 10);
      return number > 0 && number <= 0x10ffff ? String.fromCodePoint(number) : match;
    });
    return highlightPlain(text, searchTextRanges(text, query), background, foreground);
  }).join("");
}
