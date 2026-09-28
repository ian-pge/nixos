import QtQuick
import QtTest

import "../ui/Theme.js" as Theme
import "../features/usage"

// View only: a QtObject stands in for the controller, so no CLI is started.
Item {
  width: 500; height: 800
  QtObject {
    id: claudeSource
    property string name: "Claude"
    property bool loading: false
    property string error: ""
    property var snapshot: null
  }
  QtObject {
    id: codexSource
    property string name: "Codex"
    property bool loading: false
    property string error: ""
    property var snapshot: null
  }
  QtObject {
    id: controller
    readonly property var claude: claudeSource
    readonly property var codex: codexSource
    property bool loading: false
    property real updatedAt: 0
    property real now: new Date(2026, 8, 28, 15, 42).getTime()
    property var refreshes: []
    function refresh(force) { refreshes = refreshes.concat([force]); }
  }
  QtObject {
    id: state
    property int closed: 0
  }
  UsagePanel { id: panel; width: 434; controller: controller; onCloseRequested: state.closed += 1 }

  TestCase {
    name: "UsagePanel"
    when: windowShown
    readonly property real hour: 3600000
    function row(label, percent, resetsAt, reached = false) {
      return {label: label, percent: percent, resetsAt: resetsAt, reached: reached};
    }
    function init() {
      const now = controller.now;
      claudeSource.snapshot = {plan: "Claude Max", notes: [], blocked: false, limits: [
        row("Session en cours", 3, now + 4 * hour + 12 * 60000),
        row("Semaine · tous les modèles", 10, new Date(2026, 9, 2, 12, 0).getTime()),
        row("Semaine · Fable", 15, new Date(2026, 9, 2, 12, 0).getTime())]};
      codexSource.snapshot = {plan: "ChatGPT Pro Lite", blocked: false,
        notes: [{text: "1 crédit de réinitialisation", alert: false}],
        limits: [row("Semaine", 94, new Date(2026, 9, 3, 19, 17).getTime())]};
      for (const source of [claudeSource, codexSource]) { source.error = ""; source.loading = false; }
      controller.loading = false; controller.updatedAt = new Date(2026, 8, 28, 15, 41).getTime();
      controller.refreshes = []; state.closed = 0;
      panel.width = 434; panel.visible = true; panel.enabled = true;
      panel.forceActiveFocus();
      wait(0);
    }
    function child(name, parent = panel) { return findChild(parent, name); }
    function section(name) { return child(name + "Section"); }
    function limitRow(sectionName, index) { return child("limitRow" + index, section(sectionName)); }

    function test_contents_order_and_palette() {
      compare(child("usageTitle").text, "Limites d’utilisation");
      compare(child("sectionTitle", section("claude")).text, "Claude");
      compare(child("sectionTitle", section("claude")).color, Theme.usageAccent);
      compare(child("sectionPlan", section("claude")).text, "Claude Max");
      compare(child("sectionPlan", section("codex")).text, "ChatGPT Pro Lite");
      verify(section("claude").y < section("codex").y);
      const first = limitRow("claude", 0);
      compare(child("limitLabel", first).text, "Session en cours");
      compare(child("limitPercent", first).text, "3 %");
      compare(child("limitReset", first).text, "Réinitialisation dans 4 h 12");
      compare(child("limitReset", limitRow("claude", 1)).text, "Réinitialisation ven. 2 oct. à 12:00");
      compare(child("limitLabel", limitRow("claude", 2)).text, "Semaine · Fable");
      verify(child("limitRow3", section("claude")) === null);
      const week = limitRow("codex", 0), track = child("limitTrack", week), fill = child("limitFill", week);
      compare(child("limitPercent", week).text, "94 %");
      fuzzyCompare(fill.width, track.width * 0.94, 0.5);
      compare(fill.color, Theme.usageAccent);
      compare(child("limitPercent", week).color, Theme.foreground);
      compare(child("sectionNotes", section("codex")).text, "1 crédit de réinitialisation");
      verify(!child("sectionNotes", section("claude")).visible);
      compare(child("updateLabel").text, "Màj 15:41");
    }
    function test_reached_limit_and_alerts_use_the_failure_color() {
      codexSource.snapshot = {plan: "ChatGPT Plus", blocked: true,
        notes: [{text: "Limite atteinte", alert: true}, {text: "1 crédit de réinitialisation", alert: false}],
        limits: [row("Semaine", 100, controller.now + 2 * hour, true)]};
      const week = limitRow("codex", 0);
      compare(child("limitPercent", week).color, Theme.error);
      compare(child("limitFill", week).color, Theme.error);
      compare(child("limitFill", week).width, child("limitTrack", week).width);
      const notes = child("sectionNotes", section("codex")).text;
      verify(notes.includes('<font color="' + Theme.error + '">Limite atteinte</font>'));
      verify(notes.endsWith(" · 1 crédit de réinitialisation"));
    }
    function test_loading_and_errors_before_any_reading() {
      claudeSource.snapshot = null; claudeSource.loading = true; controller.loading = true;
      compare(child("sectionMessage", section("claude")).text, "Lecture des limites…");
      compare(child("sectionMessage", section("claude")).color, Theme.secondary);
      compare(child("updateLabel").text, "Actualisation…");
      claudeSource.loading = false; controller.loading = false; claudeSource.error = "Claude introuvable";
      compare(child("sectionMessage", section("claude")).text, "Claude introuvable");
      compare(child("sectionMessage", section("claude")).color, Theme.error);
      verify(child("limitRow0", section("claude")) === null);
      verify(!child("sectionMessage", section("codex")).visible);
    }
    function test_failed_refresh_keeps_rows_with_a_note() {
      claudeSource.error = "Délai dépassé";
      compare(child("limitPercent", limitRow("claude", 0)).text, "3 %");
      verify(child("sectionNotes", section("claude")).visible);
      verify(child("sectionNotes", section("claude")).text.includes("Échec de l’actualisation"));
      verify(!child("sectionMessage", section("claude")).visible);
    }
    function test_height_follows_data_not_width() {
      const full = panel.implicitHeight;
      verify(full > 300 && full < 480, "Height " + full);
      panel.width = 520;
      compare(panel.implicitHeight, full);
      claudeSource.snapshot = Object.assign({}, claudeSource.snapshot, {limits: claudeSource.snapshot.limits.slice(0, 1)});
      compare(panel.implicitHeight, full - 2 * section("claude").rowPitch);
      claudeSource.error = "Délai dépassé";
      verify(panel.implicitHeight > full - 2 * section("claude").rowPitch, "The failure note takes its own line");
      verify(section("codex").y > section("claude").y + section("claude").height);
    }
    function test_keys_close_and_refresh() {
      keyClick(Qt.Key_R);
      compare(controller.refreshes, [true]);
      keyClick(Qt.Key_Escape);
      compare(state.closed, 1);
      keyClick(Qt.Key_Q);
      compare(state.closed, 2);
      keyClick(Qt.Key_J);
      compare(state.closed, 2); compare(controller.refreshes.length, 1);
    }
  }
}
