import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui/Theme.js" as Theme
import "../../ui/TextSearch.js" as TextSearch

Rectangle {
  id: root
  objectName: "assistantCorrectionReport"
  color: "#000000"
  radius: 18
  required property var report
  signal focusRequested()
  TapHandler { onPressedChanged: if (pressed) root.focusRequested() }
  readonly property bool pending: report?.state === "running"
  // Natural height comes from the wrapped content, independently of the
  // viewport height. The notch caps it when the report needs scrolling.
  implicitHeight: reportLayout.implicitHeight + 44
  ColumnLayout {
    id: reportLayout
    anchors { fill: parent; margins: 22 }
    spacing: 18
    Rectangle {
      id: avatar
      Layout.preferredWidth: 36; Layout.preferredHeight: 36
      Layout.alignment: Qt.AlignLeft
      radius: width / 2; color: "#ffffff"; antialiasing: true
      Accessible.role: Accessible.Graphic
      Accessible.name: (root.report?.provider === "openai" ? "GPT" : "Qwen") + (root.pending ? " · Correction en cours" : "")
      property real pulseTime: 0
      scale: root.pending ? 1 + 0.06 * Math.sin(pulseTime * Math.PI * 1.25) : 1
      FrameAnimation {
        objectName: "assistantCorrectionProgress"
        running: root.pending && root.visible
        onTriggered: avatar.pulseTime += frameTime
      }
      Image {
        objectName: "assistantCorrectionLogo"
        anchors { fill: parent; margins: parent.width * 0.14 }
        source: root.report?.provider === "openai" ? "assets/openai/logo.svg" : "assets/qwen/logo.png"
        sourceSize: Qt.size(parent.width * 2, parent.width * 2)
        fillMode: Image.PreserveAspectFit
      }
    }
    ScrollView {
      id: reportScroll
      objectName: "assistantCorrectionScroll"
      Layout.fillWidth: true; Layout.fillHeight: true
      Layout.preferredHeight: reportBody.implicitHeight
      Layout.minimumHeight: 0
      contentWidth: availableWidth
      contentHeight: reportBody.implicitHeight
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      Column {
        id: reportBody
        width: reportScroll.availableWidth; spacing: 22
        Text {
          objectName: "assistantCorrectionStatus"
          width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
          visible: text.length > 0
          text: root.report?.state === "error" ? root.report?.message || "La correction n’a pas abouti."
            : root.report?.state === "cancelled" ? "Le texte a changé : ces propositions n’ont pas été appliquées."
            : root.report?.state === "undone" ? "Le texte original a été restauré."
            : root.report?.skipped ? "Les propositions incertaines ont été écartées." : ""
          color: root.report?.state === "error" ? Theme.error : Theme.secondary
          font { family: "Ubuntu Nerd Font"; pixelSize: 17 }
        }
        TextEdit {
          objectName: "assistantCorrectedText"
          width: parent.width
          text: root.pending
            ? '<p style="white-space:pre-wrap">' + TextSearch.escapeTextMarkup(root.report?.source || "").replace(/\n/g, "<br/>") + '</p>'
            : root.report?.html || ""
          textFormat: TextEdit.RichText; wrapMode: TextEdit.Wrap
          readOnly: true; selectByMouse: true; activeFocusOnPress: false
          color: Theme.foreground
          font { family: "Ubuntu Nerd Font"; pixelSize: 21 }
        }
        Repeater {
          model: root.pending ? [] : root.report?.explanations || []
          delegate: Column {
            required property var modelData
            width: parent.width; spacing: 5
            Text {
              width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
              text: modelData.from + " → " + modelData.to
              color: Theme.error; font { family: "Ubuntu Nerd Font"; pixelSize: 18; bold: true }
            }
            Text {
              width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
              text: modelData.reason
              color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: 18 }
            }
          }
        }
      }
    }
  }
}
