pragma ComponentBehavior: Bound
import QtQuick
import "../../ui/Theme.js" as Theme
import "UsageLimits.js" as Limits

// One provider: plan, optional notes, then one gauge per limit window. The
// height is derived from the data, never from a layout pass.
Item {
  id: root
  required property var source
  property url logoSource: ""
  property real now: Date.now()
  signal externalLinkRequested(string url)
  readonly property var snapshot: source.snapshot
  readonly property var limits: snapshot?.limits ?? []
  readonly property var notes: (snapshot?.notes ?? []).concat(source.error !== "" && snapshot !== null
    ? [{text: "Échec de l’actualisation", alert: true}] : [])
  readonly property string message: snapshot !== null ? ""
    : source.error !== "" ? source.error : source.loading ? "Lecture des limites…" : "Aucune donnée"
  readonly property real rowsY: notes.length > 0 ? 46 : 28
  readonly property int rowPitch: 56
  implicitHeight: limits.length > 0 ? rowsY + limits.length * rowPitch - 8 : rowsY + 18

  component Label: Text {
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 11
    height: 18
    textFormat: Text.PlainText
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }

  Image {
    id: logo
    objectName: "providerLogo"
    y: 2; width: 18; height: 18
    source: root.logoSource
    sourceSize.width: 18; sourceSize.height: 18
    fillMode: Image.PreserveAspectFit
    visible: root.logoSource.toString() !== ""
  }
  Label {
    objectName: "sectionTitle"
    x: logo.visible ? logo.width + 8 : 0
    width: Math.max(0, parent.width - x - plan.implicitWidth - 12)
    height: 22
    text: root.source.name
    font.pixelSize: 13; font.bold: true
    color: Theme.usageAccent
  }
  Label {
    id: plan
    objectName: "sectionPlan"
    anchors.right: parent.right
    height: 22
    text: root.snapshot?.plan ?? ""
  }
  Label {
    objectName: "sectionNotes"
    y: 24; width: parent.width
    visible: root.notes.length > 0
    textFormat: Text.StyledText
    linkColor: Theme.secondary
    onLinkActivated: url => root.externalLinkRequested(url)
    // Notes are fixed local strings; alerts use the explicit failure color.
    text: root.notes.map(note => note.url
      ? '<a href="' + note.url + '">' + note.text + "</a>"
      : note.alert ? '<font color="' + Theme.error + '">' + note.text + "</font>" : note.text).join(" · ")
  }
  Label {
    objectName: "sectionMessage"
    y: root.rowsY; width: parent.width
    visible: root.message !== ""
    text: root.message
    color: root.source.error !== "" ? Theme.error : Theme.secondary
  }

  Repeater {
    model: root.limits
    delegate: Item {
      id: row
      required property var modelData
      required property int index
      readonly property bool reached: modelData.reached
      objectName: "limitRow" + index
      y: root.rowsY + index * root.rowPitch
      width: root.width
      height: 48

      Label {
        objectName: "limitLabel"
        width: Math.max(0, parent.width - percent.implicitWidth - 12)
        text: row.modelData.label
        color: Theme.foreground
        font.pixelSize: 12
      }
      Label {
        id: percent
        objectName: "limitPercent"
        anchors.right: parent.right
        text: Limits.percentText(row.modelData.percent)
        color: row.reached ? Theme.error : Theme.foreground
        font.pixelSize: 12; font.bold: true
      }
      Rectangle {
        objectName: "limitTrack"
        y: 22; width: parent.width; height: 6; radius: 3
        color: Theme.surfaceRaised
        Rectangle {
          objectName: "limitFill"
          width: parent.width * Math.max(0, Math.min(1, row.modelData.percent / 100))
          height: parent.height; radius: parent.radius
          color: row.reached ? Theme.error : Theme.usageAccent
        }
      }
      Label {
        objectName: "limitReset"
        y: 32; width: parent.width; height: 16
        text: Limits.resetText(row.modelData.resetsAt, root.now)
      }
    }
  }
}
