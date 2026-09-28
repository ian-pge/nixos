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
  property alias player: player
  readonly property bool active: playWhenReady || player.playbackState === MediaPlayer.PlayingState

  function play(id, attachment) {
    if (!id) return;
    // Pause explicitly or press Escape before starting a different voice note.
    if (active && key !== id) return;
    if (key === id && !errorText) {
      if (player.playbackState === MediaPlayer.PlayingState) return;
      playWhenReady = true;
      if (!downloading && sourceUrl) player.play();
      return;
    }
    ++generation;
    player.stop();
    key = id; errorText = ""; downloading = false;
    sourceUrl = ""; playWhenReady = true;
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
  function pause() { playWhenReady = false; player.pause(); }
  function toggle(id, attachment) {
    if (key === id && active) pause();
    else play(id, attachment);
  }
  MediaPlayer {
    id: player
    objectName: "beeperAudioPlayer"
    source: root.sourceUrl
    audioOutput: AudioOutput {}
    onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) root.playWhenReady = false
    onErrorOccurred: (error, message) => { root.playWhenReady = false; root.errorText = message; }
  }
}
