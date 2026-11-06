import Quickshell
import QtQuick
import "UsageLimits.js" as Limits

// One shared pair of brief CLI reads for every bar, refreshed every five
// minutes while active. Missing startup readings retry independently until
// available: every 30 seconds initially, then once per minute.
// No per-screen collector or long-running CLI.
Scope {
  id: root
  property bool enabled: true
  property bool active: false
  // No prompt is sent: get_usage reads plan limits without inference, the
  // session is not saved, and neither MCP servers nor hooks are started.
  // The helper adds the reset-status read after the CLI has refreshed auth.
  property list<string> claudeCommand: ["node", Qt.resolvedUrl("../../../tools/quickshell/usage/claude-usage.mjs").toString().replace(/^file:\/\//, ""), "claude", "-p", "--input-format", "stream-json",
    "--output-format", "stream-json", "--verbose", "--no-session-persistence",
    "--strict-mcp-config", "--settings", "{\"disableAllHooks\":true}"]
  property list<string> codexCommand: ["codex", "app-server"]
  property string workingDirectory: Quickshell.env("HOME") || Quickshell.workingDirectory
  property int minimumInterval: 60000
  property int refreshInterval: 300000
  property int startupRetryInterval: 30000
  property int startupRetryDuration: 300000
  property int recoveryRetryInterval: 60000
  property real startupStartedAt: 0
  property int timeout: 30000
  property real lastRefresh: 0
  readonly property var claude: claudeSource
  readonly property var codex: codexSource
  readonly property bool loading: claudeSource.loading || codexSource.loading
  readonly property real updatedAt: Math.max(claudeSource.updatedAt, codexSource.updatedAt)
  readonly property real now: clock.date.getTime()

  function refresh(force = false) {
    if (!enabled) return;
    if (!force && lastRefresh > 0 && Date.now() - lastRefresh < minimumInterval) return;
    // A slow provider must not prevent the other from refreshing. Each source
    // guards its own process, including the asynchronous start/exit interval.
    const claudeStarted = claudeSource.start();
    const codexStarted = codexSource.start();
    if (claudeStarted || codexStarted) lastRefresh = Date.now();
  }
  function expired() {
    return Limits.expired(claudeSource.snapshot, Date.now())
      || Limits.expired(codexSource.snapshot, Date.now());
  }
  function startupRetriesAllowed() {
    return enabled && active && startupWindow.running
      && Date.now() - startupStartedAt < startupRetryDuration;
  }
  function scheduleStartupRetry() {
    startupRetry.stop();
    if (!enabled || !active) return;
    const pending = [claudeSource, codexSource].filter(source =>
      source.snapshot === null && !source.loading && source.lastStartedAt > 0);
    if (pending.length === 0) return;
    const retryInterval = startupRetriesAllowed() ? startupRetryInterval : recoveryRetryInterval;
    const nextAttempt = Math.min(...pending.map(source => source.lastCompletedAt + retryInterval));
    startupRetry.interval = Math.max(1, nextAttempt - Date.now());
    startupRetry.start();
  }
  function retryInitialUsage() {
    if (!enabled || !active) return;
    const now = Date.now();
    const retryInterval = startupRetriesAllowed() ? startupRetryInterval : recoveryRetryInterval;
    for (const source of [claudeSource, codexSource]) {
      if (source.snapshot === null && !source.loading && source.lastStartedAt > 0
          && now - source.lastCompletedAt >= retryInterval)
        source.start();
    }
    scheduleStartupRetry();
  }
  function refreshWhenActive() {
    if (!enabled || !active) {
      startupRetry.stop();
      return;
    }
    // Once per controller lifetime, not on each visibility/enable change.
    if (startupStartedAt === 0) {
      startupStartedAt = Date.now();
      startupWindow.start();
    }
    refresh();
    scheduleStartupRetry();
  }

  onActiveChanged: Qt.callLater(root.refreshWhenActive)
  onEnabledChanged: Qt.callLater(root.refreshWhenActive)
  Component.onCompleted: if (enabled && active) Qt.callLater(root.refreshWhenActive)
  // Re-read a window at its reset time instead of assuming a fresh allowance.
  onNowChanged: if (active && expired()) refresh()

  SystemClock { id: clock; precision: SystemClock.Minutes }
  Timer {
    id: startupWindow
    interval: root.startupRetryDuration
    onTriggered: root.scheduleStartupRetry()
  }
  Timer {
    id: startupRetry
    onTriggered: root.retryInitialUsage()
  }
  Timer {
    interval: root.refreshInterval
    repeat: true
    running: root.enabled && root.active
    onTriggered: root.refresh()
  }
  UsageSource {
    id: claudeSource
    name: "Claude"
    command: root.claudeCommand
    protocol: Limits.claude
    timeout: root.timeout
    workingDirectory: root.workingDirectory
    onLoadingChanged: Qt.callLater(root.scheduleStartupRetry)
  }
  UsageSource {
    id: codexSource
    name: "Codex"
    command: root.codexCommand
    protocol: Limits.codex
    timeout: root.timeout
    workingDirectory: root.workingDirectory
    onLoadingChanged: Qt.callLater(root.scheduleStartupRetry)
  }
}
