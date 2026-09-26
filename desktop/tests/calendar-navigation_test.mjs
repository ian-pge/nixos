import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const calendar = vm.createContext({ Theme: {} });
vm.runInContext(readFileSync(new URL("../features/calendar/Calendar.js", import.meta.url), "utf8")
  .replace(/^\.(pragma|import).*$/gm, ""), calendar);
const source = readFileSync(new URL("../features/calendar/CalendarController.qml", import.meta.url), "utf8");
const state = vm.createContext({ Calendar: calendar,
  today: calendar.localDate(2026, 8, 10), detailsOpen: true });
for (const name of ["goToday", "selectDate", "moveDay", "moveMonth"]) {
  const match = source.match(new RegExp(`^  function ${name}\\([^]*?^  }`, "m"));
  assert.ok(match, name);
  vm.runInContext(match[0], state);
}
state.goToday();
assert.equal(state.selectedDate, "2026-09-10");
assert.equal(state.detailsOpen, false);
assert.equal(state.followsToday, true);
state.moveDay(7);
assert.equal(state.selectedDate, "2026-09-17");
assert.equal(state.followsToday, false);
state.selectDate("2026-12-31", true);
state.moveDay(1);
assert.equal(state.selectedDate, "2027-01-01");
assert.equal(state.detailsOpen, true);
assert.equal(state.year, 2027);
assert.equal(state.month, 0);
state.selectDate("2024-01-31", true);
state.moveMonth(1);
assert.equal(state.selectedDate, "2024-02-29");
assert.equal(state.detailsOpen, false);
state.selectDate("2026-03-31");
state.moveMonth(-1);
assert.equal(state.selectedDate, "2026-02-28");
state.selectDate("2026-03-28");
state.moveDay(2);
assert.equal(state.selectedDate, "2026-03-30", "Local dates must survive DST");
state.selectDate("0001-01-01");
state.moveDay(-1);
assert.equal(state.selectedDate, "0001-01-01");
state.selectDate("9999-12-31");
state.moveMonth(1);
assert.equal(state.selectedDate, "9999-12-31");
console.log("PASS: shared calendar selection, day/month boundaries, leap years, DST and detail state");
