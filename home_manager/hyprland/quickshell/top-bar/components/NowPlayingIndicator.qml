import Quickshell.Services.Mpris
import QtQuick

Item {
  id: root

  required property var statusData
  readonly property var player: statusData.mprisPlayer
  readonly property bool playing: player !== null && player.isPlaying

  implicitWidth: 300
  implicitHeight: 36

  Item {
    id: equalizer
    anchors.left: parent.left
    anchors.leftMargin: 10
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
        color: "#ff33cc"

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

  Rectangle {
    id: artworkFrame
    anchors.left: equalizer.right
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    width: 28
    height: 28
    radius: 7
    color: "#363a4f"
    clip: true

    Image {
      id: artwork
      anchors.fill: parent
      source: root.player !== null ? root.player.trackArtUrl : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
    }

    Text {
      visible: artwork.status !== Image.Ready
      anchors.centerIn: parent
      text: "󰎈"
      color: "#ff33cc"
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 15
      font.bold: true
    }
  }

  Text {
    id: playbackIcon
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    text: root.player !== null && root.player.isPlaying ? "󰏤" : "󰐊"
    color: root.player !== null && root.player.isPlaying ? "#a6da95" : "#ff33cc"
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 16
    font.bold: true
  }

  Text {
    anchors.left: artworkFrame.right
    anchors.leftMargin: 10
    anchors.right: playbackIcon.left
    anchors.rightMargin: 12
    y: 3
    height: 16
    verticalAlignment: Text.AlignVCenter
    text: root.player !== null && root.player.trackTitle !== ""
      ? root.player.trackTitle : "Unknown track"
    color: "#cad3f5"
    elide: Text.ElideRight
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 13
    font.bold: true
  }

  Text {
    anchors.left: artworkFrame.right
    anchors.leftMargin: 10
    anchors.right: playbackIcon.left
    anchors.rightMargin: 12
    y: 18
    height: 14
    verticalAlignment: Text.AlignVCenter
    text: root.player !== null && root.player.trackArtist !== ""
      ? root.player.trackArtist : root.player !== null ? root.player.identity : ""
    color: "#939ab7"
    elide: Text.ElideRight
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 11
    font.bold: true
  }
}
