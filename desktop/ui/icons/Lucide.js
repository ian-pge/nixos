.pragma library
.import "LucideData.js" as Data

function has(name) { return Object.prototype.hasOwnProperty.call(Data.icons, name); }
function source(name, color, strokeWidth) {
  if (!name) return "";
  const body = has(name) ? Data.icons[name] : Data.icons["circle-question-mark"];
  const rgb = [color.r, color.g, color.b].map(channel => Math.round(channel * 255)).join(",");
  return "data:image/svg+xml;charset=utf-8," + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none"'
    + ' stroke="rgb(' + rgb + ')" stroke-opacity="' + color.a + '" stroke-width="' + strokeWidth
    + '" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>');
}
