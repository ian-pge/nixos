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
      usage.enabled = false;
      tryCompare(usage, "loading", false, 10000);
      usage.destroy();
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/usage/UsageController.qml");
      usage = component.createObject(root, {timeout: 5000});
      verify(usage !== null);
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
      tryVerify(() => usage.loading);
      tryCompare(usage, "loading", false, 10000);
      compare(usage.claude.run, runs + 1); compare(usage.codex.run, runs + 1);
      compare(usage.claude.error, ""); compare(usage.codex.error, "");
      compare(usage.claude.snapshot.plan, "Claude Max");
      compare(usage.claude.snapshot.notes[0].text, "Réinitialisations : voir Claude");
      compare(usage.claude.snapshot.notes[0].url, "https://claude.ai/settings/usage");
      compare(labels(usage.claude), ["Session en cours 3", "Semaine · tous les modèles 10", "Semaine · Fable 15"]);
      verify(usage.claude.snapshot.limits[0].resetsAt > Date.now());
      compare(usage.codex.snapshot.plan, "ChatGPT Pro Lite");
      compare(labels(usage.codex), ["5 heures 12", "Semaine 94"]);
      compare(usage.codex.snapshot.notes[0].text, "1 crédit de réinitialisation");
      compare(usage.codex.snapshot.resetCredits, 1);
      compare(usage.claude.snapshot.resetCredits, null);
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
    function test_visible_bar_refreshes_periodically_and_stops_when_inactive() {
      const interval = usage.refreshInterval, minimum = usage.minimumInterval;
      try {
        usage.refreshInterval = 100; usage.minimumInterval = 0;
        const claudeRuns = usage.claude.run, codexRuns = usage.codex.run;
        usage.active = true;
        tryVerify(() => usage.claude.run >= claudeRuns + 2 && usage.codex.run >= codexRuns + 2, 5000);
        usage.active = false;
        tryCompare(usage, "loading", false, 5000);
        const stopped = usage.claude.run;
        wait(250); compare(usage.claude.run, stopped);
      } finally {
        usage.active = false;
        usage.refreshInterval = interval; usage.minimumInterval = minimum;
      }
    }
    function test_startup_retry_defaults() {
      compare(usage.startupRetryInterval, 30000);
      compare(usage.startupRetryDuration, 300000);
      compare(usage.refreshInterval, 300000);
      compare(usage.minimumInterval, 60000);
    }
    function test_startup_retries_only_missing_source_and_stops_on_success() {
      usage.startupRetryInterval = 150;
      usage.startupRetryDuration = 2000;
      modes("exit", "ok");
      usage.active = true;
      tryVerify(() => usage.codex.snapshot !== null);
      tryVerify(() => usage.claude.run >= 2, 1000);
      compare(usage.codex.run, 1, "A healthy provider must not be polled every 30 seconds");
      // Startup retries bypass the normal one-minute throttle.
      compare(usage.minimumInterval, 60000);
      modes("ok", "ok");
      tryVerify(() => usage.claude.snapshot !== null, 1500);
      tryCompare(usage, "loading", false);
      const runs = usage.claude.run;
      wait(350);
      compare(usage.claude.run, runs);
      compare(usage.codex.run, 1);
      const startedAt = usage.startupStartedAt;
      usage.active = false;
      wait(30);
      usage.active = true;
      wait(200);
      compare(usage.startupStartedAt, startedAt, "Visibility does not restart the five-minute window");
      compare(usage.claude.run, runs);
    }
    function test_startup_retry_window_expires_and_normal_polling_continues() {
      usage.startupRetryInterval = 120;
      usage.startupRetryDuration = 650;
      usage.refreshInterval = 1400;
      usage.minimumInterval = 0;
      modes("exit", "error");
      usage.active = true;
      tryVerify(() => usage.claude.run >= 2 && usage.codex.run >= 2, 600);
      tryVerify(() => !usage.startupRetriesAllowed(), 1000);
      tryCompare(usage, "loading", false);
      const claudeRuns = usage.claude.run, codexRuns = usage.codex.run;
      wait(300);
      compare(usage.claude.run, claudeRuns);
      compare(usage.codex.run, codexRuns);
      tryVerify(() => usage.claude.run > claudeRuns && usage.codex.run > codexRuns, 1500);
    }
    function test_startup_retries_stop_when_disabled_and_do_not_extend_window() {
      usage.startupRetryInterval = 100;
      usage.startupRetryDuration = 450;
      modes("exit", "error");
      usage.active = true;
      tryVerify(() => usage.claude.run >= 1);
      usage.enabled = false;
      tryCompare(usage, "loading", false);
      const runs = usage.claude.run, startedAt = usage.startupStartedAt;
      wait(550);
      compare(usage.claude.run, runs);
      usage.enabled = true;
      wait(250);
      compare(usage.startupStartedAt, startedAt);
      compare(usage.claude.run, runs);
    }
    function test_startup_timeout_retries_without_overlapping_processes() {
      usage.startupRetryInterval = 80;
      usage.startupRetryDuration = 1500;
      usage.timeout = 250;
      modes("hang", "ok");
      usage.active = true;
      tryVerify(() => usage.claude.loading);
      const firstAttempt = usage.claude.lastStartedAt;
      wait(120);
      compare(usage.claude.run, 1, "Never start a second process while the first is running");
      tryVerify(() => usage.claude.run >= 2, 1000);
      verify(usage.claude.lastStartedAt - firstAttempt >= 250);
      modes("ok", "ok");
      tryVerify(() => usage.claude.snapshot !== null, 1500);
      compare(usage.codex.run, 1);
    }
    function test_startup_retry_is_not_blocked_by_other_provider() {
      usage.startupRetryInterval = 100;
      usage.startupRetryDuration = 1000;
      usage.timeout = 600;
      modes("exit", "hang");
      usage.active = true;
      tryVerify(() => usage.claude.run >= 2, 500);
      verify(usage.codex.loading);
      compare(usage.codex.run, 1);
      usage.active = false;
    }
    function test_later_failure_does_not_restart_fast_polling() {
      usage.startupRetryInterval = 100;
      usage.startupRetryDuration = 1500;
      usage.active = true;
      tryVerify(() => usage.claude.snapshot !== null && usage.codex.snapshot !== null);
      tryCompare(usage, "loading", false);
      modes("exit", "error");
      refreshAndWait();
      const runs = usage.claude.run;
      wait(300);
      compare(usage.claude.run, runs);
      verify(usage.claude.snapshot !== null);
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
