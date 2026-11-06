import QtQuick
import QtMultimedia
import Quickshell
import "./BeeperFormat.js" as Format

// Shared across conversations, monitors and recycled message delegates.
Scope {
  id: root
  required property var beeperData
  property string key: ""
  property string sourceUrl: ""
  property bool downloading: false
  property bool playWhenReady: false
  property string errorText: ""
  property int generation: 0
  property var pausedPositions: ({})
  property real pendingPosition: 0
  property alias player: player
  readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
  readonly property bool active: playWhenReady || playing

  function play(id, attachment) {
    if (!id) return;
    if (key === id && !errorText) {
      if (player.playbackState === MediaPlayer.PlayingState) return;
      playWhenReady = true;
      if (!downloading && sourceUrl) player.play();
      return;
    }
    ++generation;
    // Keep one decoder, but let each interrupted vocal resume where it paused.
    // Advancing the generation also cancels an older pending download.
    pause();
    if (key && sourceUrl && !errorText) {
      const position = player.mediaStatus === MediaPlayer.EndOfMedia ? 0 : pendingPosition || player.position;
      pausedPositions = Object.assign({}, pausedPositions, {[key]: position});
    }
    pendingPosition = 0;
    player.stop();
    key = id; errorText = ""; downloading = false;
    sourceUrl = ""; playWhenReady = true;
    pendingPosition = pausedPositions[id] || 0;
    const source = Format.attachmentSource(attachment);
    if (/^(file:|https?:|data:)/.test(source)) { sourceUrl = source; player.play(); return; }
    const url = attachment.srcURL || attachment.url || attachment.id || "";
    if (!url) { playWhenReady = false; errorText = "Audio unavailable"; return; }
    const requestGeneration = generation;
    downloading = true;
    beeperData.request("download", {url: url}, (result, error) => {
      if (requestGeneration !== generation) return;
      downloading = false;
      if (error || !result?.srcURL || result.error) {
        playWhenReady = false; errorText = error?.message || result?.error || "Audio unavailable"; return;
      }
      sourceUrl = result.srcURL;
      if (playWhenReady) player.play();
    });
  }
  function restorePosition() {
    // A new source is seekable only once Qt has loaded its metadata.
    if (!pendingPosition || !player.seekable || player.duration <= 0
        || ![MediaPlayer.LoadedMedia, MediaPlayer.BufferingMedia, MediaPlayer.BufferedMedia].includes(player.mediaStatus)) return;
    const position = pendingPosition;
    pendingPosition = 0;
    player.setPosition(position < player.duration ? position : 0);
  }
  function pause() { playWhenReady = false; player.pause(); }
  function seek(delta) {
    if (!player.seekable || player.duration <= 0) return;
    player.setPosition(Math.max(0, Math.min(player.duration, player.position + delta)));
  }
  function toggle(id, attachment) {
    if (key === id && active) pause();
    else play(id, attachment);
  }
  // This player lives as long as the shell: an AudioOutput keeps the device
  // it was created with, so follow the default that the audio panel changes.
  MediaDevices { id: devices }
  MediaPlayer {
    id: player
    objectName: "beeperAudioPlayer"
    source: root.sourceUrl
    audioOutput: AudioOutput { device: devices.defaultAudioOutput }
    onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) root.playWhenReady = false
    onMediaStatusChanged: root.restorePosition()
    onSeekableChanged: root.restorePosition()
    onErrorOccurred: (error, message) => { root.playWhenReady = false; root.errorText = message; }
  }
}
