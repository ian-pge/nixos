import Quickshell
import QtQuick
import "./Calendar.js" as Calendar

// Calendar selection and weather state; the shell alone decides when/where to show it.
Scope {
  id: root
  property bool enabled: true
  property var weather: weatherData
  property date today: clock.date
  property int year: today.getFullYear()
  property int month: today.getMonth()
  property bool followsToday: true
  property string selectedDate: Calendar.dateKey(today)
  property bool detailsOpen: false
  readonly property string timeText: Qt.formatDateTime(today, "HH:mm")
  readonly property string dateText: Qt.formatDateTime(today, "dd/MM/yy")
  onTodayChanged: if (followsToday) goToday()

  SystemClock { id: clock; precision: SystemClock.Minutes }
  WeatherData { id: weatherData; autoRefresh: root.enabled && root.weather === weatherData }

  function goToday() {
    year = today.getFullYear();
    month = today.getMonth();
    followsToday = true;
    selectedDate = Calendar.dateKey(today);
    detailsOpen = false;
  }

  function selectDate(key, openDetails = false) {
    const date = Calendar.dateFromKey(key);
    if (!isFinite(date.getTime()) || date.getFullYear() < 1 || date.getFullYear() > 9999)
      return;
    selectedDate = Calendar.dateKey(date);
    year = date.getFullYear();
    month = date.getMonth();
    followsToday = false;
    if (openDetails)
      detailsOpen = true;
  }

  function moveDay(delta) {
    const date = Calendar.dateFromKey(selectedDate);
    date.setDate(date.getDate() + delta);
    selectDate(Calendar.dateKey(date));
  }

  function moveMonth(delta) {
    const date = Calendar.localDate(year, month + delta, 1);
    if (date.getFullYear() < 1 || date.getFullYear() > 9999)
      return;
    const selected = Calendar.dateFromKey(selectedDate);
    const lastDay = Calendar.localDate(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    date.setDate(Math.min(selected.getDate(), lastDay));
    selectDate(Calendar.dateKey(date));
    detailsOpen = false;
  }
}
