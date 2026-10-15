import QtQuick
import "../../ui/Theme.js" as Theme
import "../../ui"

Rectangle {
  id: root
  objectName: "voiceDictationIndicator"

  required property var controller
  readonly property bool recording: controller.recording
  readonly property color accent: Theme.action

  implicitWidth: Theme.barSize(180)
  implicitHeight: Theme.barSize(36)
  radius: Theme.barSize(18)
  color: GlassState.enabled ? "transparent" : Theme.background

  VoiceWaveform {
    objectName: "dictationWaveform"
    sizeScale: Theme.barScale
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Theme.barSize(10)
    anchors.verticalCenter: parent.verticalCenter
    height: Theme.barSize(22)
    energy: root.controller.energy
    speechDetected: root.controller.speechDetected
    accent: root.accent
    active: root.recording
    visible: root.recording
  }

  Row {
    anchors.centerIn: parent
    spacing: Theme.barSize(10)
    visible: !root.recording

    Icon {
      anchors.verticalCenter: parent.verticalCenter
      name: "loader-circle"; spinning: true
      color: root.accent
      size: Theme.barSize(17)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Transcription…"
      color: root.accent
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: Theme.barSize(14)
      font.bold: true
    }
  }
}
