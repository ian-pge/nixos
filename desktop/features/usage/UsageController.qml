import Quickshell
import QtQuick
import "UsageLimits.js" as Limits

// One shared pair of brief CLI reads for every bar, refreshed every five
// minutes while active. No per-screen collector or long-running CLI.
Scope {
  id: root
  property bool enabled: true
  property bool active: false
  // No prompt is sent: get_usage reads plan limits without inference, the
  // session is not saved, and neither MCP servers nor hooks are started.
  property list<string> claudeCommand: ["claude", "-p", "--input-format", "stream-json",
    "--output-format", "stream-json", "--verbose", "--no-session-persistence",
    "--strict-mcp-config", "--settings", "{\"disableAllHooks\":true}"]
  property list<string> codexCommand: ["codex", "app-server"]
  property string workingDirectory: Quickshell.env("HOME") || Quickshell.workingDirectory
  property int minimumInterval: 60000
  property int refreshInterval: 300000
  property int timeout: 30000
  property real lastRefresh: 0
  readonly property var claude: claudeSource
  readonly property var codex: codexSource
  readonly property bool loading: claudeSource.loading || codexSource.loading
  readonly property real updatedAt: Math.max(claudeSource.updatedAt, codexSource.updatedAt)
  readonly property real now: clock.date.getTime()

  function refresh(force = false) {
    if (!enabled || loading) return;
    if (!force && lastRefresh > 0 && Date.now() - lastRefresh < minimumInterval) return;
    lastRefresh = Date.now();
    claudeSource.start();
    codexSource.start();
  }
  function expired() {
    return Limits.expired(claudeSource.snapshot, Date.now())
      || Limits.expired(codexSource.snapshot, Date.now());
  }
  function refreshWhenActive() { if (active) refresh(); }

  onActiveChanged: if (active) Qt.callLater(root.refreshWhenActive)
  onEnabledChanged: if (enabled && active) Qt.callLater(root.refreshWhenActive)
  Component.onCompleted: if (enabled && active) Qt.callLater(root.refreshWhenActive)
  // Re-read a window at its reset time instead of assuming a fresh allowance.
  onNowChanged: if (active && expired()) refresh()

  SystemClock { id: clock; precision: SystemClock.Minutes }
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
  }
  UsageSource {
    id: codexSource
    name: "Codex"
    command: root.codexCommand
    protocol: Limits.codex
    timeout: root.timeout
    workingDirectory: root.workingDirectory
  }
}
