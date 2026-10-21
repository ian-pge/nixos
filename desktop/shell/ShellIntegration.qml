import QtQuick
import Quickshell
import Quickshell.Io

// The public IPC names stay stable; these are commands, not compatibility
// aliases for feature state. The rest of the UI talks to its own controllers.
Scope {
  id: root
  required property var services
  required property var coordinator
  required property var messenger
  property bool enabled: true
  function border(overlay) {
    if (!enabled) return;
    Quickshell.execDetached(["hyprctl", "keyword", "general:col.active_border",
      overlay ? "rgba(888888aa)" : "rgba(33ff33ff)"]);
  }
  Component.onCompleted: border(false)
  Component.onDestruction: border(false)
  Connections {
    target: root.coordinator
    function onHighlightFocusedWindowChanged() { root.border(root.coordinator.highlightFocusedWindow); }
  }
  IpcHandler {
    target: "topbar"
    // Read-only diagnostics for the actual bar; no second Bluetooth subscriber.
    function batteryStatus(): string {
      const power = root.services.power;
      const relay = power.phoneRelay;
      return JSON.stringify({
        configured: relay.configured, connected: relay.connected,
        receiverRunning: relay.transport !== null,
        phoneAgeMs: relay.snapshot === null ? null : relay.now - relay.snapshot.observedAt,
        phoneReportAgeMs: relay.snapshot === null ? null : relay.now - relay.snapshot.receivedAt,
        phoneMode: relay.snapshot?.mode ?? null,
        phone: power.phoneBatteries, fitbit: power.fitbitBatteries,
        mouse: power.mouseBatteries, keyboard: power.keyboardBatteries,
        earbuds: power.earbudBatteries, earbudDataConnected: power.earbudDataConnected,
        earbudAudioConnected: power.earbudAudioConnected,
        earbudReceiverRunning: power.earbudsData.transport !== null,
        earbudAgeMs: power.earbudsData.snapshot === null ? null
          : power.earbudsData.now - power.earbudsData.snapshot.observedAt,
        earbudMode: power.earbudsData.snapshot?.mode ?? null,
        earbudReportAgeMs: power.earbudsData.snapshot === null ? null
          : power.earbudsData.now - power.earbudsData.snapshot.receivedAt,
        earbudSource: power.earbudsData.available ? "fast-pair" : null
      });
    }
    function toggleBeeper() { root.messenger.toggle(); }
    function dismissNotification() { root.services.notifications.close(); }
    function toggleDoNotDisturb() { root.services.notifications.toggleDoNotDisturb(); }
    function refreshNix() { root.services.updates.refreshStatus(); }
    function mediaPlayPause() { root.services.media.playPause(); }
    function mediaNext() { root.services.media.next(); }
    function mediaPrevious() { root.services.media.previous(); }
    function volumeUp() { root.services.audio.setVolume(root.services.audio.volumeStep); root.coordinator.showVolume(); }
    function volumeDown() { root.services.audio.setVolume(-root.services.audio.volumeStep); root.coordinator.showVolume(); }
    function toggleAudioMute() { if (root.services.audio.toggleMute()) root.coordinator.showVolume(); }
    function toggleAudio() { root.coordinator.toggle("audio"); }
    function toggleCalendar() { root.coordinator.toggle("calendar"); }
    function toggleUsage() { root.services.usage.refresh(true); }
    function toggleStorage() { root.coordinator.toggle("storage"); }
    function toggleMicrophoneMute() {
      if (root.services.audio.toggleMicrophoneMute()) root.coordinator.showMicrophoneFeedback();
    }
    function showVolume() { root.coordinator.showVolume(); }
    function showBrightness() { root.coordinator.showBrightness(); }
    function brightnessUp() { root.services.brightness.change(5, root.coordinator.resolveMonitor()); }
    function brightnessDown() { root.services.brightness.change(-5, root.coordinator.resolveMonitor()); }
    function toggleWifi() { root.coordinator.toggle("wifi"); }
    function toggleBluetooth() { root.coordinator.toggle("bluetooth"); }
    function toggleUpdates() { root.coordinator.toggle("updates"); }
    function toggleLauncher() { root.coordinator.toggle("launcher"); }
  }
}
