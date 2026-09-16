import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const calendar = vm.createContext({ Theme: {} });
vm.runInContext(readFileSync(new URL("../components/Calendar.js", import.meta.url), "utf8")
  .replace(/^\.(pragma|import).*$/gm, ""), calendar);
const source = readFileSync(new URL("../StatusData.qml", import.meta.url), "utf8");
const state = vm.createContext({ Calendar: calendar,
  calendarToday: calendar.localDate(2026, 8, 10), calendarDetailsOpen: true });
for (const name of ["calendarGoToday", "calendarSelectDate", "calendarMoveDay", "calendarMoveMonth"]) {
  const match = source.match(new RegExp(`^  function ${name}\\([^]*?^  }`, "m"));
  assert.ok(match, name);
  vm.runInContext(match[0], state);
}
state.calendarGoToday();
assert.equal(state.calendarSelectedDate, "2026-09-10");
assert.equal(state.calendarDetailsOpen, false);
assert.equal(state.calendarFollowsToday, true);
state.calendarMoveDay(7);
assert.equal(state.calendarSelectedDate, "2026-09-17");
assert.equal(state.calendarFollowsToday, false);
state.calendarSelectDate("2026-12-31", true);
state.calendarMoveDay(1);
assert.equal(state.calendarSelectedDate, "2027-01-01");
assert.equal(state.calendarDetailsOpen, true);
assert.equal(state.calendarYear, 2027);
assert.equal(state.calendarMonth, 0);
state.calendarSelectDate("2024-01-31", true);
state.calendarMoveMonth(1);
assert.equal(state.calendarSelectedDate, "2024-02-29");
assert.equal(state.calendarDetailsOpen, false);
state.calendarSelectDate("2026-03-31");
state.calendarMoveMonth(-1);
assert.equal(state.calendarSelectedDate, "2026-02-28");
state.calendarSelectDate("2026-03-28");
state.calendarMoveDay(2);
assert.equal(state.calendarSelectedDate, "2026-03-30", "Local dates must survive DST");
state.calendarSelectDate("0001-01-01");
state.calendarMoveDay(-1);
assert.equal(state.calendarSelectedDate, "0001-01-01");
state.calendarSelectDate("9999-12-31");
state.calendarMoveMonth(1);
assert.equal(state.calendarSelectedDate, "9999-12-31");
console.log("PASS: shared calendar selection, day/month boundaries, leap years, DST and detail state");
