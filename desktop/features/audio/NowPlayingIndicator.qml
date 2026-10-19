import QtQuick
import "../../ui"
import "../../ui/Layout.js" as Layout
import "../../ui/Theme.js" as Theme

Item {
  id: root
  objectName: "nowPlayingIndicator"

  required property var controller
  readonly property var player: controller.player
  readonly property bool playing: controller.playing
  readonly property string labelText: controller.labelText
  readonly property string playbackIconText: controller.playbackIconText

  implicitWidth: Layout.boundedWidth(Theme.barSize(15) + Theme.barSize(18) + Theme.barSize(10)
    + labelMetrics.advanceWidth(labelText) + Theme.barSize(12)
    + Theme.barSize(16) + Theme.barSize(14), Theme.barSize(160), Theme.barSize(480))
  implicitHeight: Theme.barSize(36)

  FontMetrics {
    id: labelMetrics
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: Theme.barSize(16)
    font.bold: true
  }

  Item {
    id: equalizer
    objectName: "mediaEqualizer"
    anchors.left: parent.left
    anchors.leftMargin: Theme.barSize(15)
    anchors.verticalCenter: parent.verticalCenter
    width: Theme.barSize(18)
    height: Theme.barSize(20)

    Repeater {
      model: 4

      Rectangle {
        id: equalizerBar
        objectName: "mediaEqualizerBar" + index
        required property int index
        property real level: 4 + (index % 2) * 2

        x: index * 5 * Theme.barScale
        anchors.bottom: parent.bottom
        width: 3 * Theme.barScale
        height: level * Theme.barScale
        radius: 1.5 * Theme.barScale
        color: root.playing ? Theme.yellow : Theme.inactive

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

  Icon {

    size: Theme.barSize(16)
    id: playbackIcon
    objectName: "mediaPlaybackIcon"
    anchors.right: parent.right
    anchors.rightMargin: Theme.barSize(14)
    anchors.verticalCenter: parent.verticalCenter
    name: root.playbackIconText
    color: Theme.yellow

  }

  Text {
    objectName: "mediaLabel"
    anchors.left: equalizer.right
    anchors.leftMargin: Theme.barSize(10)
    anchors.right: playbackIcon.left
    anchors.rightMargin: Theme.barSize(12)
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    text: root.labelText
    color: Theme.foreground
    elide: Text.ElideRight
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: Theme.barSize(16)
    font.bold: true
  }
}
