import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Scope {
  id: root

  // Only visibility is supplied by the shell; this controller never chooses a surface.
  property bool enabled: true
  property bool selectorVisible: false
  readonly property real volumeStep: 0.05
  readonly property var sink: enabled ? Pipewire.defaultAudioSink : null
  readonly property var microphoneSource: enabled ? Pipewire.defaultAudioSource : null
  readonly property var microphone: microphoneSource !== null ? microphoneSource.audio : null
  readonly property bool microphoneAvailable: microphoneSource !== null
    && microphoneSource.ready && microphone !== null
  readonly property bool microphoneMuted: microphoneAvailable && microphone.muted
  readonly property var devices: enabled ? Pipewire.nodes.values.filter(node =>
    !node.isStream && node.audio !== null) : []
  readonly property var outputs: devices.filter(node => node.isSink)
  readonly property var inputs: devices.filter(node => !node.isSink
    && !audioAvailability.unavailableNames[node.name])
  AudioAvailability {
    id: audioAvailability
    enabled: root.enabled && root.selectorVisible
  }
  readonly property var audio: sink !== null ? sink.audio : null
  readonly property bool muted: audio !== null && audio.muted
  readonly property int volume: audio !== null
    ? Math.round(audio.volume * 100)
    : 0


  function icon() {
    if (muted)
      return "󰖁";
    if (volume < 34)
      return "󰕿";
    if (volume < 67)
      return "󰖀";
    return "󰕾";
  }

  function setVolume(delta) {
    if (audio === null)
      return;
    audio.volume = Math.max(0, Math.min(1, audio.volume + delta));
  }

  function deviceLabel(node) {
    return node.nickname || node.description || node.name;
  }

  function selectDevice(node) {
    // Re-check membership: a device may disappear between key press and dispatch.
    if (!Pipewire.ready || node === null || !node.ready
        || !(node.isSink ? outputs : inputs).includes(node))
      return;
    if (node.isSink)
      Pipewire.preferredDefaultAudioSink = node;
    else
      Pipewire.preferredDefaultAudioSource = node;
  }

  function toggleMicrophoneMute() {
    if (!microphoneAvailable)
      return false;
    microphone.muted = !microphone.muted;
    return true;
  }

  function toggleMute() {
    if (audio === null)
      return false;
    audio.muted = !audio.muted;
    return true;
  }


  Loader {
    active: root.enabled
    sourceComponent: Component {
      PwObjectTracker {
        objects: root.selectorVisible ? root.devices
          : [root.sink, root.microphoneSource].filter(node => node !== null)
      }
    }
  }
}
