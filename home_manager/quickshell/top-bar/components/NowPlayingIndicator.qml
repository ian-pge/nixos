import Quickshell.Services.Mpris
import QtQuick
import "Layout.js" as Layout
import "Theme.js" as Theme

Item {
  id: root

  required property var statusData
  readonly property var player: statusData.mprisPlayer
  readonly property bool playing: player !== null && player.isPlaying
  readonly property string labelText: {
    const title = player !== null && player.trackTitle !== ""
      ? player.trackTitle : "Unknown track";
    const artist = player !== null && player.trackArtist !== ""
      ? player.trackArtist : player !== null ? player.identity : "";
    return artist !== "" ? title + "  •  " + artist : title;
  }
  readonly property string playbackIconText: player !== null && player.isPlaying
    ? "󰏤" : "󰐊"

  implicitWidth: Layout.boundedWidth(15 + 18 + 10
    + labelMetrics.advanceWidth(labelText) + 12
    + playbackMetrics.advanceWidth(playbackIconText) + 14, 160, 480)
  implicitHeight: 36

  FontMetrics {
    id: labelMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 16
    font.bold: true
  }

  FontMetrics {
    id: playbackMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 16
    font.bold: true
  }

  Item {
    id: equalizer
    anchors.left: parent.left
    anchors.leftMargin: 15
    anchors.verticalCenter: parent.verticalCenter
    width: 18
    height: 20

    Repeater {
      model: 4

      Rectangle {
        id: equalizerBar
        required property int index
        property real level: 4 + (index % 2) * 2

        x: index * 5
        anchors.bottom: parent.bottom
        width: 3
        height: level
        radius: 1.5
        color: root.playing ? Theme.state : Theme.inactive

        SequentialAnimation {
          id: barAnimation
          running: root.playing
          loops: Animation.Infinite
          onRunningChanged: {
            if (!running)
              equalizerBar.level = 4 + (equalizerBar.index % 2) * 2;
          }

          NumberAnimation {
            target: equalizerBar
            property: "level"
            to: 14 + (equalizerBar.index % 2) * 4
            duration: 110 + equalizerBar.index * 17
            easing.type: Easing.InOutQuad
          }
          NumberAnimation {
            target: equalizerBar
            property: "level"
            to: 6 + ((equalizerBar.index + 1) % 3) * 3
            duration: 90 + equalizerBar.index * 13
            easing.type: Easing.InOutQuad
          }
          NumberAnimation {
            target: equalizerBar
            property: "level"
            to: 17 - equalizerBar.index * 2
            duration: 120 + (3 - equalizerBar.index) * 19
            easing.type: Easing.InOutQuad
          }
          NumberAnimation {
            target: equalizerBar
            property: "level"
            to: 4 + (equalizerBar.index % 2) * 2
            duration: 100 + equalizerBar.index * 11
            easing.type: Easing.InOutQuad
          }
        }
      }
    }
  }

  Text {
    id: playbackIcon
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    text: root.playbackIconText
    color: Theme.action
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 16
    font.bold: true
  }

  Text {
    anchors.left: equalizer.right
    anchors.leftMargin: 10
    anchors.right: playbackIcon.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: root.labelText
    color: Theme.foreground
    elide: Text.ElideRight
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 16
    font.bold: true
  }
}
