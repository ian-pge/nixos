import QtQuick
import QtQuick.Layouts
import "Theme.js" as Theme
import "BeeperFormat.js" as Format

Item {
  id: root
  required property var message
  property var beeperData: null
  property bool selected: false
  property bool playbackEnabled: true
  readonly property bool outgoing: !!message.isSender
  readonly property bool groupMessage: beeperData?.currentChat?.type === "group"
  readonly property color senderColor: groupMessage
    ? (beeperData.senderColors[Format.senderKey(message)] || Theme.sideApplications)
    : Theme.sideApplications
  signal selectedRequested()
  signal actionsRequested()
  signal previewRequested(var attachment)
  implicitHeight: contents.implicitHeight + 22

  Rectangle {
    anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
    radius: 14; color: root.selected ? Qt.alpha(Theme.sideApplications, 0.07) : "transparent"
    border.width: root.selected ? 1 : 0; border.color: Qt.alpha(Theme.sideApplications, 0.25)
  }
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; onClicked: mouse => { root.selectedRequested(); if (mouse.button === Qt.RightButton) root.actionsRequested(); } }
  Column {
    id: contents
    width: Math.min(parent.width * 0.86, 680)
    anchors { right: root.outgoing ? parent.right : undefined; left: root.outgoing ? undefined : parent.left; margins: 16; top: parent.top; topMargin: 10 }
    spacing: 5
    Text {
      visible: !root.outgoing
      text: root.message.senderName || "Contact"
      color: root.senderColor
      font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label; weight: Font.Medium }
    }
    Rectangle {
      width: root.message.attachments?.length ? parent.width : Math.min(parent.width, Math.max(110, body.implicitWidth + 28))
      height: bubble.implicitHeight + 22
      anchors.right: root.outgoing ? parent.right : undefined
      radius: 15
      color: root.groupMessage ? Qt.tint(Qt.alpha(Theme.surfaceRaised, 0.55), Qt.alpha(root.senderColor, 0.08))
        : root.outgoing ? Qt.alpha(Theme.sideApplications, 0.13) : Qt.alpha(Theme.surfaceRaised, 0.55)
      border.width: root.groupMessage ? 1 : 0
      border.color: Qt.alpha(root.senderColor, 0.16)
      Column {
        id: bubble
        width: parent.width - 28
        x: 14; y: 11; spacing: 8
        Text { visible: !!root.message.linkedMessageID; text: "↪ En réponse à un message"; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
        Text {
          id: body
          objectName: "messageBody"
          width: parent.width
          visible: !!text
          text: Format.text(root.message)
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: Theme.foreground
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.body }
          lineHeight: 1.2
        }
        Repeater {
          model: root.message.attachments || []
          BeeperMedia {
            required property var modelData
            width: bubble.width
            attachment: modelData; beeperData: root.beeperData
            playbackEnabled: root.playbackEnabled
            onPreviewRequested: attachment => root.previewRequested(attachment)
          }
        }
        Repeater {
          model: Format.links(root.message)
          BeeperButton {
            required property var modelData
            width: bubble.width
            text: "↗  " + (modelData.title || modelData.url)
            prominent: true
            onClicked: Qt.openUrlExternally(modelData.url)
          }
        }
      }
    }
    Row {
      anchors.right: root.outgoing ? parent.right : undefined
      spacing: 8
      Text { text: Format.time(root.message.timestamp); color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
      Text { visible: root.outgoing; text: root.message.sendStatus?.status === "PENDING" ? "Envoi…" : String(root.message.sendStatus?.status || "").startsWith("FAIL") ? "Échec" : "✓"; color: String(root.message.sendStatus?.status || "").startsWith("FAIL") ? Theme.error : Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
      Repeater {
        model: root.message.reactions || []
        Text { required property var modelData; text: (modelData.reactionKey || modelData.emoji || "♡") + (modelData.count > 1 ? " " + modelData.count : ""); color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      }
    }
  }
}
