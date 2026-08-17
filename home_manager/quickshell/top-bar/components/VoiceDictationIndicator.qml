import QtQuick
import "Theme.js" as Theme

Rectangle {
  id: root

  required property var statusData
  readonly property bool recording: statusData.voiceDictationRecording
  readonly property color accent: Theme.action

  implicitWidth: 180
  implicitHeight: 36
  radius: 18
  color: Theme.background

  VoiceWaveform {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 10
    anchors.verticalCenter: parent.verticalCenter
    height: 22
    energy: root.statusData.voiceDictationEnergy
    speechDetected: root.statusData.voiceDictationSpeechDetected
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
      text: root.statusData.brailleFrame
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
