import QtQuick
import "../../ui/Theme.js" as Theme
import "../../ui"

Rectangle {
  id: root

  required property var controller
  readonly property bool recording: controller.recording
  readonly property color accent: Theme.action

  implicitWidth: 180
  implicitHeight: 36
  radius: 18
  color: GlassState.enabled ? "transparent" : Theme.background

  VoiceWaveform {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 10
    anchors.verticalCenter: parent.verticalCenter
    height: 22
    energy: root.controller.energy
    speechDetected: root.controller.speechDetected
    accent: root.accent
    active: root.recording
    visible: root.recording
  }

  Row {
    anchors.centerIn: parent
    spacing: 10
    visible: !root.recording

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.controller.brailleFrame
      color: root.accent
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 17
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Transcription…"
      color: root.accent
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 14
      font.bold: true
    }
  }
}
