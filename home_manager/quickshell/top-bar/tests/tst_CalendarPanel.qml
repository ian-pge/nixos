import QtQuick
import QtTest
import "../components"
import "../components/Calendar.js" as Calendar
import "../components/Theme.js" as Theme

Item {
  width: 500
  height: 520
  QtObject {
    id: weather
    readonly property var initialDays: ({
      "2026-09-10": {code: 0, temperatureMinC: 0, temperatureMaxC: 12.5},
      "2026-09-11": {code: 95, temperatureMinC: -3.5, temperatureMaxC: 0},
      "2026-09-12": {code: null, temperatureMinC: null, temperatureMaxC: null}})
    property var days: initialDays
    property string locationText: "Paris"
    property string updateText: "Màj 10/09 14:00"
    property bool loading: false
    property bool locationSearchOpen: false
    property string locationQuery: ""
    property var locationResults: []
    property string locationSearchError: ""
    property bool searchingLocations: false
    property var chosenLocation: undefined
    function openLocationSearch() { locationSearchOpen = true; setLocationQuery(""); }
    function closeLocationSearch() { locationSearchOpen = false; }
    function setLocationQuery(query) { locationQuery = query; }
    function chooseLocation(location) { chosenLocation = location; closeLocationSearch(); }
  }
  QtObject {
    id: state
    property var weather: weather
    property date calendarToday: Calendar.localDate(2026, 8, 10)
    property int calendarYear: 2026
    property int calendarMonth: 8
    property string calendarSelectedDate: "2026-09-10"
    property bool calendarDetailsOpen: false
    property bool closed: false
    function calendarMoveMonth(delta) {
      const date = Calendar.localDate(calendarYear, calendarMonth + delta, 1);
      date.setDate(Math.min(Calendar.dateFromKey(calendarSelectedDate).getDate(),
        Calendar.localDate(date.getFullYear(), date.getMonth() + 1, 0).getDate()));
      calendarSelectDate(Calendar.dateKey(date));
      calendarDetailsOpen = false;
    }
    function calendarSelectDate(key, details = false) {
      const date = Calendar.dateFromKey(key);
      calendarYear = date.getFullYear(); calendarMonth = date.getMonth();
      calendarSelectedDate = key;
      if (details) calendarDetailsOpen = true;
    }
    function calendarMoveDay(delta) {
      const date = Calendar.dateFromKey(calendarSelectedDate);
      date.setDate(date.getDate() + delta);
      calendarSelectDate(Calendar.dateKey(date));
    }
    function calendarGoToday() {
      calendarSelectDate(Calendar.dateKey(calendarToday));
      calendarDetailsOpen = false;
    }
    function hideCalendar() { closed = true; }
  }
  CalendarPanel {
    id: panel
    width: 434
    height: implicitHeight
    statusData: state
  }
  TestCase {
    name: "CalendarPanel"
    when: windowShown

    function init() {
      weather.closeLocationSearch();
      weather.locationResults = [];
      weather.chosenLocation = undefined;
      weather.days = weather.initialDays;
      state.calendarToday = Calendar.localDate(2026, 8, 10);
      state.calendarGoToday();
      state.closed = false;
      panel.width = 434;
      panel.visible = true;
      panel.enabled = true;
      panel.forceActiveFocus();
      tryCompare(panel, "activeFocus", true);
      wait(0);
    }

    function test_months_data() {
      return [{tag: "February", year: 2026, month: 1, days: 28, offset: 6},
        {tag: "leap year", year: 2024, month: 1, days: 29, offset: 3},
        {tag: "century not leap", year: 2100, month: 1, days: 28, offset: 0},
        {tag: "June Monday", year: 2026, month: 5, days: 30, offset: 0},
        {tag: "August six rows", year: 2026, month: 7, days: 31, offset: 5},
        {tag: "February four rows", year: 2027, month: 1, days: 28, offset: 0}];
    }
    function test_months(row) {
      const cells = Calendar.monthCells(row.year, row.month);
      compare(cells.length, Math.ceil((row.offset + row.days) / 7) * 7);
      compare(cells.filter(cell => cell.day > 0).length, row.days);
      compare(cells.findIndex(cell => cell.day === 1), row.offset);
      compare(cells[row.offset + row.days - 1].day, row.days);
      verify(cells.every(cell => cell.day === 0 ? cell.date === "" : cell.date.length === 10));
    }
    function test_weather_codes_data() {
      return [{tag: "sun", code: 0, icon: "\ue30d"}, {tag: "clear", code: 1, icon: "\ue302"},
        {tag: "cloud", code: 3, icon: "\ue312"}, {tag: "fog", code: 48, icon: "\ue313"},
        {tag: "drizzle", code: 51, icon: "\ue318"}, {tag: "rain", code: 65, icon: "\ue318"},
        {tag: "snow", code: 75, icon: "\ue31a"}, {tag: "showers", code: 82, icon: "\ue319"},
        {tag: "storm", code: 99, icon: "\ue31d"}, {tag: "null", code: null, icon: ""},
        {tag: "unknown", code: 1000, icon: ""}, {tag: "missing", code: undefined, icon: ""}];
    }
    function test_weather_codes(row) { compare(Calendar.weatherIcon(row.code), row.icon); }
    function test_temperature_ranges() {
      compare(Calendar.temperatureRange(weather.days["2026-09-10"]), "0°/13°");
      compare(Calendar.temperatureRange(weather.days["2026-09-11"]), "-3°/0°");
      for (const day of [undefined, null, {}, {temperatureMinC: null, temperatureMaxC: 12},
          {temperatureMinC: 0, temperatureMaxC: NaN}, {temperatureMinC: "0", temperatureMaxC: 12}])
        compare(Calendar.temperatureRange(day), "");
    }
    function test_dates_keep_local_day() {
      for (const date of [[2026, 2, 29], [2026, 9, 25], [2026, 11, 31], [2027, 0, 1]]) {
        const local = Calendar.localDate(date[0], date[1], date[2]);
        compare(local.getFullYear(), date[0]); compare(local.getMonth(), date[1]); compare(local.getDate(), date[2]);
        compare(Calendar.dateKey(local), date[0] + "-" + String(date[1] + 1).padStart(2, "0") + "-" + String(date[2]).padStart(2, "0"));
      }
    }
    function test_day_contents_and_stable_geometry() {
      compare(panel.monthTitle, "Septembre 2026");
      const today = findChild(panel, "2026-09-10");
      verify(today.isToday); compare(today.weatherIcon, "\ue30d");
      compare(today.temperatureText, "0°/13°");
      compare(findChild(panel, "2026-09-11").weatherIcon, "\ue31d");
      compare(findChild(panel, "2026-09-12").weatherIcon, "");
      compare(findChild(panel, "2026-09-30").weatherIcon, "");
      compare(findChild(panel, "2026-09-30").temperatureText, "");
      for (const day of [today, findChild(panel, "2026-09-11")]) {
        const icon = findChild(day, "weatherIcon");
        compare(icon.color, day === today ? Theme.weatherSun : Theme.weatherRain);
        compare(icon.font.family, "Ubuntu Nerd Font");
        const temperature = findChild(day, "temperature");
        compare(temperature.color, Theme.sideWeather);
        verify(temperature.y + temperature.height <= day.height);
        verify(temperature.contentWidth <= temperature.width);
      }
      const height = panel.implicitHeight;
      panel.width = 500;
      wait(0);
      compare(panel.implicitHeight, height);
      state.calendarMonth = 7;
      compare(panel.cells.length, 42);
    }
    function fillWeather(year, month, throughDay) {
      const days = {};
      for (const cell of Calendar.monthCells(year, month)) {
        if (cell.day > 0 && cell.day <= throughDay)
          days[cell.date] = {code: 3, temperatureMinC: 12, temperatureMaxC: 23};
      }
      weather.days = days;
    }
    function verifyFooter() {
      const grid = findChild(panel, "dayGrid");
      const footer = findChild(panel, "updateLabel");
      compare(footer.y, grid.y + grid.height + 10);
      compare(panel.implicitHeight, footer.y + footer.height + 10);
    }
    function test_dynamic_height_data() {
      return [{tag: "September partial forecast", year: 2026, month: 8, throughDay: 25, rows: 5, height: 392},
        {tag: "September full forecast", year: 2026, month: 8, throughDay: 30, rows: 5, height: 428},
        {tag: "August six full rows", year: 2026, month: 7, throughDay: 31, rows: 6, height: 492},
        {tag: "August no weather", year: 2026, month: 7, throughDay: 0, rows: 6, height: 276},
        {tag: "February four compact rows", year: 2027, month: 1, throughDay: 0, rows: 4, height: 220}];
    }
    function test_dynamic_height(row) {
      state.calendarYear = row.year;
      state.calendarMonth = row.month;
      fillWeather(row.year, row.month, row.throughDay);
      compare(panel.weeks.length, row.rows);
      tryCompare(panel, "implicitHeight", row.height);
      verifyFooter();
      // Native rows keep weekday columns aligned regardless of their heights.
      for (let index = 0; index < row.rows; index++) {
        const week = findChild(panel, "week" + index);
        const cells = week.children.filter(child => child.modelData !== undefined);
        compare(cells.length, 7);
        for (let column = 0; column < 7; column++) {
          compare(cells[column].height, week.height);
          tryVerify(() => Math.abs(cells[column].x - column * (cells[column].width + 4)) < 0.01);
        }
      }
    }
    function test_weather_updates_grow_and_shrink_last_week() {
      fillWeather(2026, 8, 25);
      tryCompare(panel, "implicitHeight", 392);
      compare(findChild(panel, "week4").height, 24);
      const days = Object.assign({}, weather.days);
      days["2026-09-30"] = {code: 0, temperatureMinC: null, temperatureMaxC: null};
      weather.days = days;
      tryCompare(panel, "implicitHeight", 412);
      compare(findChild(panel, "week4").height, 44);
      fillWeather(2026, 8, 30);
      tryCompare(panel, "implicitHeight", 428);
      compare(findChild(panel, "week4").height, 60);
      weather.days = {};
      tryCompare(panel, "implicitHeight", 248);
      verifyFooter();
    }
    function test_hidden_height_updates_without_layout_pass() {
      panel.visible = false;
      state.calendarMonth = 7;
      weather.days = {};
      compare(panel.implicitHeight, 276);
      fillWeather(2026, 7, 31);
      compare(panel.implicitHeight, 492);
      weather.days = {};
      compare(panel.implicitHeight, 276);
      state.calendarMonth = 8;
      compare(panel.implicitHeight, 248);
      panel.visible = true;
    }
    function test_keyboard_and_year_boundary() {
      state.calendarSelectDate("2026-12-31");
      keyClick(Qt.Key_Right);
      compare(state.calendarYear, 2027); compare(state.calendarMonth, 0);
      compare(state.calendarSelectedDate, "2027-01-01");
      keyClick(Qt.Key_Left);
      compare(state.calendarYear, 2026); compare(state.calendarMonth, 11);
      keyClick(Qt.Key_Home);
      compare(state.calendarMonth, 8);
      keyClick(Qt.Key_Escape);
      verify(state.closed);
    }
    function test_vim_days_months_and_details() {
      keyClick(Qt.Key_H);
      compare(state.calendarSelectedDate, "2026-09-09");
      keyClick(Qt.Key_J);
      compare(state.calendarSelectedDate, "2026-09-16");
      keyClick(Qt.Key_K);
      compare(state.calendarSelectedDate, "2026-09-09");
      keyClick(Qt.Key_L);
      compare(state.calendarSelectedDate, "2026-09-10");
      keyClick(Qt.Key_Return);
      verify(state.calendarDetailsOpen);
      keyClick(Qt.Key_L);
      compare(state.calendarSelectedDate, "2026-09-11");
      verify(state.calendarDetailsOpen);
      keyClick(Qt.Key_Escape);
      verify(!state.calendarDetailsOpen); verify(!state.closed);
      keyClick(Qt.Key_U);
      compare(state.calendarSelectedDate, "2026-08-11");
      keyClick(Qt.Key_D);
      compare(state.calendarSelectedDate, "2026-09-11");
      keyClick(Qt.Key_Enter);
      verify(state.calendarDetailsOpen);
      verify(panel.activeFocus); verify(!state.closed);
      keyClick(Qt.Key_N);
      compare(state.calendarSelectedDate, "2026-09-10");
      verify(!state.calendarDetailsOpen);
      keyClick(Qt.Key_U);
      keyClick(Qt.Key_N);
      compare(state.calendarSelectedDate, "2026-09-10");
      compare(state.calendarMonth, 8);
    }
    function test_no_buttons_and_cover_dont_reset_month() {
      for (const name of ["previousMonth", "today", "nextMonth"])
        verify(findChild(panel, name) === null);
      keyClick(Qt.Key_D);
      compare(state.calendarMonth, 9);
      panel.enabled = false;
      panel.enabled = true;
      wait(0);
      compare(state.calendarMonth, 9);
      keyClick(Qt.Key_U);
      compare(state.calendarMonth, 8);
      state.calendarMonth = 0;
      keyClick(Qt.Key_Home);
      compare(state.calendarMonth, 8);
    }
    function test_mouse_day_and_back() {
      const day = findChild(panel, "2026-09-11");
      mouseClick(day, day.width / 2, day.height / 2);
      compare(state.calendarSelectedDate, "2026-09-11");
      verify(state.calendarDetailsOpen);
      verify(findChild(panel, "dayDetails").visible);
      const back = findChild(panel, "backToCalendar");
      mouseClick(back, back.width / 2, back.height / 2);
      verify(!state.calendarDetailsOpen);
      verify(findChild(panel, "2026-09-11").isSelected);
      const selected = findChild(panel, "2026-09-11");
      const today = findChild(panel, "2026-09-10");
      tryCompare(selected, "color", today.color);
      compare(selected.radius, today.radius);
      compare(selected.border.width, today.border.width);
      compare(selected.border.color, Theme.calendarSelected);
      compare(today.border.color, Theme.sideWeather);
      compare(findChild(selected, "dayNumber").color, Theme.calendarSelected);
      verify(findChild(selected, "dayNumber").font.bold);
      keyClick(Qt.Key_N);
      compare(today.border.color, Theme.calendarSelected);
    }
    function test_location_search_keyboard_keeps_calendar_keys_as_text() {
      keyClick(Qt.Key_S);
      verify(weather.locationSearchOpen);
      const input = findChild(panel, "locationSearchInput");
      tryCompare(input, "activeFocus", true);
      keyClick(Qt.Key_S); keyClick(Qt.Key_U); keyClick(Qt.Key_N);
      compare(input.text, "sun");
      compare(state.calendarSelectedDate, "2026-09-10");
      weather.locationResults = [{name: "Sun City", region: "Arizona", country: "États-Unis",
        latitude: 33.6, longitude: -112.3}];
      wait(0);
      keyClick(Qt.Key_Return);
      compare(weather.chosenLocation.name, "Sun City");
      verify(!weather.locationSearchOpen);
      tryCompare(panel, "activeFocus", true);
      keyClick(Qt.Key_S);
      tryCompare(input, "activeFocus", true);
      weather.locationResults = [];
      keyClick(Qt.Key_Return);
      compare(weather.chosenLocation.name, "Sun City");
      verify(weather.locationSearchOpen);
      compare(findChild(panel, "locationResults").count, 0);
    }
    function test_location_search_escape_and_mouse() {
      keyClick(Qt.Key_Return);
      verify(state.calendarDetailsOpen);
      keyClick(Qt.Key_S);
      verify(weather.locationSearchOpen);
      const input = findChild(panel, "locationSearchInput");
      tryCompare(input, "activeFocus", true);
      keyClick(Qt.Key_Escape);
      verify(!weather.locationSearchOpen);
      verify(state.calendarDetailsOpen);
      tryCompare(panel, "activeFocus", true);
      keyClick(Qt.Key_S);
      weather.locationResults = [{name: "Lyon", region: "Auvergne-Rhône-Alpes", country: "France",
        latitude: 45.75, longitude: 4.85}];
      const list = findChild(panel, "locationResults");
      tryCompare(list, "count", 1);
      wait(0);
      mouseClick(list, 100, 23);
      compare(weather.chosenLocation.name, "Lyon");
      verify(!weather.locationSearchOpen);
    }
    function test_hourly_details_and_scroll() {
      const days = Object.assign({}, weather.days);
      days["2026-09-10"] = {code: 0, temperatureMinC: 0, temperatureMaxC: 12.5,
        hours: Array.from({length: 24}, (_, i) => ({time: String(i).padStart(2, "0") + ":00",
          code: i < 12 ? 0 : 61, temperatureC: 0, apparentTemperatureC: -1,
          precipitationProbability: 0, precipitationMm: 0, windKmh: 12, gustsKmh: 20}))};
      weather.days = days;
      keyClick(Qt.Key_Return);
      const list = findChild(panel, "weatherHours");
      compare(list.count, 24);
      compare(findChild(panel, "dayDetails").implicitHeight, 358);
      keyClick(Qt.Key_J);
      verify(list.contentY > 0);
      keyClick(Qt.Key_K);
      compare(list.contentY, 0);
      keyClick(Qt.Key_L);
      compare(list.count, 0);
      verify(findChild(panel, "hourlyEmpty").visible);
      compare(state.calendarSelectedDate, "2026-09-11");
      keyClick(Qt.Key_Escape);
      keyClick(Qt.Key_Escape);
      verify(state.closed);
    }
  }
}
