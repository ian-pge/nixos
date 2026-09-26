import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

// Native, accessible controls; no nested card or decorative fake waveform.
RowLayout {
  id: root
  required property var player
  property real fallbackDuration: 0
  property color accent: Theme.sideApplications
  property bool accentBackground: false
  property var peaks: []
  readonly property real duration: Math.max(0, player.duration || fallbackDuration)
  readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
  implicitHeight: 44
  spacing: 12

  function seek(delta) {
    if (player.seekable) player.setPosition(Math.max(0, Math.min(duration, player.position + delta)));
  }
  function barPeak(index, count) {
    const start = Math.floor(index * peaks.length / count), end = Math.max(start + 1, Math.floor((index + 1) * peaks.length / count));
    let maximum = 0;
    for (let i = start; i < end; ++i) maximum = Math.max(maximum, Number(peaks[i]) || 0);
    return Math.max(0, Math.min(1, maximum));
  }
  Button {
    id: play
    objectName: "beeperMediaPlay"
    Layout.preferredWidth: 38; Layout.preferredHeight: 38
    focusPolicy: Qt.TabFocus
    Accessible.name: root.playing ? "Pause" : "Play"
    onClicked: root.playing ? root.player.pause() : root.player.play()
    background: Rectangle {
      radius: width / 2
      color: Qt.alpha(root.accent, play.down ? 0.3 : play.hovered || play.activeFocus ? 0.23 : 0.15)
    }
    contentItem: Text {
      text: root.playing ? "󰏤" : "󰐊"
      color: root.enabled ? root.accent : Theme.inactive
      horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
      font { family: "Ubuntu Nerd Font"; pixelSize: 23 }
    }
  }
  Slider {
    id: progress
    objectName: "beeperMediaSeek"
    Layout.fillWidth: true; Layout.minimumWidth: 36; Layout.preferredHeight: 36
    padding: 0
    from: 0; to: Math.max(1, root.duration)
    value: root.player.position
    enabled: root.player.seekable && root.duration > 0
    focusPolicy: Qt.TabFocus
    wheelEnabled: false
    Accessible.name: "Playback position"
    onMoved: root.player.setPosition(value)
    Keys.onPressed: event => {
      if (event.key === Qt.Key_H || event.key === Qt.Key_L) {
        root.seek(event.key === Qt.Key_H ? -5000 : 5000); event.accepted = true;
      }
    }
    background: Item {
      id: track
      objectName: "beeperWaveform"
      x: progress.leftPadding; y: (progress.height - height) / 2
      width: progress.availableWidth; height: root.peaks.length ? 32 : 4
      readonly property int barCount: Math.min(root.peaks.length, Math.max(1, Math.floor(width / 5)))
      Repeater {
        model: track.barCount
        Rectangle {
          required property int index
          objectName: "beeperWaveformBar"
          width: 3; radius: 1.5
          height: 2 + (track.height - 2) * root.barPeak(index, track.barCount)
          x: index * track.width / track.barCount; y: (track.height - height) / 2
          color: Qt.alpha(root.accent, (index + 0.5) / track.barCount <= progress.visualPosition ? 1 : 0.5)
        }
      }
      Rectangle {
        anchors.fill: parent; visible: !root.peaks.length; radius: 2
        color: Qt.alpha(root.accent, 0.18)
        Rectangle { width: parent.width * progress.visualPosition; height: parent.height; radius: 2; color: root.accent }
      }
    }
    handle: Rectangle {
      x: progress.leftPadding + progress.visualPosition * (progress.availableWidth - width)
      y: (progress.height - height) / 2
      width: 10; height: 10; radius: 5; color: root.accent
      opacity: progress.hovered || progress.pressed || progress.activeFocus ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 100 } }
    }
  }
  Text {
    objectName: "beeperMediaTime"
    Layout.preferredWidth: 44
    text: Format.duration(root.player.position > 0 ? root.player.position : root.duration)
    horizontalAlignment: Text.AlignRight
    color: root.accentBackground ? Theme.background : Theme.secondary
    font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
  }
  BeeperButton {
    objectName: "beeperMediaRate"
    Layout.preferredWidth: 42; Layout.preferredHeight: 32
    padding: 4; text: root.player.playbackRate + "×"
    font.pixelSize: Theme.beeperFont.caption
    prominent: root.accentBackground; accent: root.accent
    Accessible.name: "Playback speed " + root.player.playbackRate + " times"
    onClicked: root.player.playbackRate = root.player.playbackRate >= 2 ? 1 : root.player.playbackRate + 0.5
  }
}
