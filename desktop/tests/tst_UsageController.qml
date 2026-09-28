import Quickshell
import QtQuick
import QtTest

// Only the fake CLIs in fixtures/ are started: no request reaches Anthropic or OpenAI.
ShellRoot {
  id: root
  property var usage: null
  readonly property string fixtures: Quickshell.shellDir + "/fixtures/"
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/usage/UsageController.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString()); Qt.exit(1); return;
    }
    usage = component.createObject(root, {timeout: 5000});
  }
  TestResult { id: results }
  TestCase {
    name: "UsageController"
    when: root.usage !== null
    function cleanupTestCase() {
      console.log("UsageController: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount > 0 ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function init() {
      usage.active = false;
      tryCompare(usage, "loading", false, 10000);
      usage.enabled = true; usage.lastRefresh = 0; usage.timeout = 5000;
      for (const source of [usage.claude, usage.codex]) {
        source.snapshot = null; source.error = ""; source.updatedAt = 0; source.killDelay = 3000;
      }
      modes("ok", "ok");
    }
    function modes(claude, codex) {
      usage.claudeCommand = [root.fixtures + "fake-claude-usage", claude];
      usage.codexCommand = [root.fixtures + "fake-codex-usage", codex];
    }
    function refreshAndWait() {
      usage.refresh(true);
      verify(usage.loading);
      tryCompare(usage, "loading", false, 10000);
    }
    function labels(source) { return source.snapshot.limits.map(row => row.label + " " + row.percent); }

    function test_opening_reads_both_plans_once() {
      const runs = usage.claude.run;
      usage.active = true;
      verify(usage.loading);
      tryCompare(usage, "loading", false, 10000);
      compare(usage.claude.run, runs + 1); compare(usage.codex.run, runs + 1);
      compare(usage.claude.error, ""); compare(usage.codex.error, "");
      compare(usage.claude.snapshot.plan, "Claude Max");
      compare(labels(usage.claude), ["Session en cours 3", "Semaine · tous les modèles 10", "Semaine · Fable 15"]);
      verify(usage.claude.snapshot.limits[0].resetsAt > Date.now());
      compare(usage.codex.snapshot.plan, "ChatGPT Pro Lite");
      compare(labels(usage.codex), ["5 heures 12", "Semaine 94"]);
      compare(usage.codex.snapshot.notes[0].text, "1 crédit de réinitialisation");
      verify(usage.updatedAt > 0);
      // Reopening within a minute reuses the answer; R still forces a read.
      usage.active = false; usage.active = true;
      verify(!usage.loading);
      compare(usage.claude.run, runs + 1);
      refreshAndWait();
      compare(usage.claude.run, runs + 2);
    }
    function test_disabled_controller_never_starts_a_cli() {
      const runs = usage.claude.run;
      usage.enabled = false;
      usage.active = true; usage.refresh(true);
      verify(!usage.loading);
      compare(usage.claude.run, runs); compare(usage.codex.run, runs);
      compare(usage.claude.snapshot, null);
    }
    function test_snapshot_answer_uses_named_windows() {
      modes("snapshot", "ok");
      refreshAndWait();
      compare(labels(usage.claude), ["Session en cours 9", "Semaine · tous les modèles 10", "Semaine · Fable 15"]);
    }
    function test_account_without_plan_limits() {
      modes("api-key", "error");
      refreshAndWait();
      compare(usage.claude.snapshot, null);
      compare(usage.claude.error, "Aucune limite d’abonnement pour ce compte");
      compare(usage.codex.snapshot, null);
      compare(usage.codex.error, "Limites Codex indisponibles");
    }
    function test_failed_refresh_keeps_previous_limits() {
      refreshAndWait();
      const updatedAt = usage.claude.updatedAt;
      modes("refused", "ok");
      refreshAndWait();
      compare(usage.claude.error, "Claude Code a refusé la lecture");
      compare(usage.claude.updatedAt, updatedAt);
      compare(labels(usage.claude).length, 3, "The last good reading stays visible");
      compare(usage.codex.error, "");
    }
    function test_codex_limit_reached_is_blocked() {
      modes("ok", "reached");
      refreshAndWait();
      compare(usage.codex.snapshot.plan, "ChatGPT Plus");
      verify(usage.codex.snapshot.blocked);
      verify(usage.codex.snapshot.limits[0].reached);
      compare(usage.codex.snapshot.notes[0].text, "Limite atteinte");
      verify(usage.codex.snapshot.notes[0].alert);
    }
    function test_missing_or_silent_cli_is_reported() {
      usage.claudeCommand = [root.fixtures + "missing-claude-usage"];
      usage.codexCommand = [root.fixtures + "fake-claude-usage", "exit"];
      usage.refresh(true);
      tryCompare(usage, "loading", false, 10000);
      compare(usage.claude.error, "Claude introuvable");
      compare(usage.codex.error, "Codex s’est arrêté sans répondre");
    }
    function test_unanswered_cli_times_out_and_is_stopped() {
      usage.timeout = 300;
      usage.claude.killDelay = 200;
      usage.claudeCommand = [root.fixtures + "fake-claude-usage", "stubborn"];
      usage.codexCommand = [root.fixtures + "fake-codex-usage", "hang"];
      usage.refresh(true);
      tryCompare(usage.claude, "error", "Délai dépassé", 3000);
      compare(usage.codex.error, "Délai dépassé");
      // SIGTERM ends the hung server; the CLI ignoring it is killed.
      tryCompare(usage, "loading", false, 3000);
      modes("ok", "ok");
      usage.timeout = 5000;
      refreshAndWait();
      compare(usage.claude.error, ""); compare(usage.codex.error, "");
    }
  }
}
