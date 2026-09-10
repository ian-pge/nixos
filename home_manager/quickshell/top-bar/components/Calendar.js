.pragma library

const monthNames = ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
  "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"];

function localDate(year, month, day) {
  const date = new Date(2000, 0, 1, 12);
  date.setFullYear(year, month, day);
  return date;
}

function dateKey(date) {
  return String(date.getFullYear()).padStart(4, "0") + "-"
    + String(date.getMonth() + 1).padStart(2, "0") + "-"
    + String(date.getDate()).padStart(2, "0");
}

function monthTitle(year, month) {
  return monthNames[month] + " " + year;
}

function monthCells(year, month) {
  const first = localDate(year, month, 1);
  const offset = (first.getDay() + 6) % 7;
  const count = localDate(year, month + 1, 0).getDate();
  const cellCount = Math.ceil((offset + count) / 7) * 7;
  return Array.from({length: cellCount}, (_, index) => {
    const day = index - offset + 1;
    return day < 1 || day > count ? {day: 0, date: ""}
      : {day: day, date: dateKey(localDate(year, month, day))};
  });
}

// Nerd Font weather glyphs are monochrome and follow the widget accent.
function weatherIcon(code) {
  switch (code) {
    case 0: return "\ue30d";
    case 1: case 2: return "\ue302";
    case 3: return "\ue312";
    case 45: case 48: return "\ue313";
    case 51: case 53: case 55: case 56: case 57:
    case 61: case 63: case 65: case 66: case 67: return "\ue318";
    case 71: case 73: case 75: case 77: case 85: case 86: return "\ue31a";
    case 80: case 81: case 82: return "\ue319";
    case 95: case 96: case 99: return "\ue31d";
    default: return "";
  }
}

function temperatureRange(day) {
  if (day === null || typeof day !== "object") return "";
  const format = value => typeof value === "number" && isFinite(value)
    ? Math.round(value) + "°" : "";
  const minimum = format(day.temperatureMinC);
  const maximum = format(day.temperatureMaxC);
  // Do not silently present a partial range as the whole day's temperature.
  return minimum !== "" && maximum !== "" ? minimum + "/" + maximum : "";
}
