import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Scope {
  id: root
  property bool enabled: true
  property var players: enabled ? Mpris.players.values : []
  readonly property var player: {
    const controllable = players.filter(item => item.canControl);
    return controllable.find(item => item.dbusName.includes("playerctld"))
      ?? controllable.find(item => item.isPlaying)
      ?? controllable.find(item => item.playbackState === MprisPlaybackState.Paused)
      ?? controllable[0] ?? null;
  }
  readonly property bool playing: player !== null && player.isPlaying
  readonly property string labelText: {
    const title = player !== null && player.trackTitle !== "" ? player.trackTitle : "Unknown track";
    const artist = player !== null && player.trackArtist !== ""
      ? player.trackArtist : player !== null ? player.identity : "";
    return artist !== "" ? title + "  •  " + artist : title;
  }
  readonly property string playbackIconText: playing ? "󰏤" : "󰐊"
  signal feedbackRequested(string monitor)

  // Metadata/track changes never request an OSD: voice messages also use MPRIS.
  function playPause(monitor = "") {
    if (player === null) return;
    if (player.canTogglePlaying) player.togglePlaying();
    else if (player.isPlaying && player.canPause) player.pause();
    else if (!player.isPlaying && player.canPlay) player.play();
    feedbackRequested(monitor);
  }
  function next(monitor = "") {
    if (player === null || !player.canGoNext) return;
    player.next(); feedbackRequested(monitor);
  }
  function previous(monitor = "") {
    if (player === null || !player.canGoPrevious) return;
    player.previous(); feedbackRequested(monitor);
  }
}
