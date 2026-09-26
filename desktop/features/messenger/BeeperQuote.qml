import QtQuick
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

// Shared by received/sent replies and the composer. The quote is plain text;
// it never starts media playback or inserts the original into paged history.
Rectangle {
  id: root
  objectName: "beeperQuote"
  required property var beeperData
  property string messageID: ""
  property bool active: true
  property real textScale: 1
  readonly property var quote: beeperData ? beeperData.quote(messageID) : ({state: "missing", message: null})
  readonly property var original: quote.state === "ready" ? quote.message : null
  readonly property color accent: original
    ? beeperData.senderColors[Format.senderKey(original)] || Theme.sideApplications : Theme.secondary
  readonly property string author: original ? (original.isSender ? "You" : original.senderName || "Contact") : "Reply"
  readonly property string preview: original ? Format.quotePreview(original)
    : quote.state === "idle" || quote.state === "loading" ? "Loading original message…" : "Original message unavailable"
  visible: !!messageID
  implicitWidth: Math.max(authorLabel.implicitWidth, previewLabel.implicitWidth) + 24
  implicitHeight: quoteColumn.implicitHeight + 16
  // Composite against the dark surface so sent replies keep the same quote
  // colors as received replies, regardless of the surrounding network accent.
  radius: 8; color: Qt.tint(Theme.surface, Qt.alpha(accent, 0.08))
  clip: true
  function resolve() { if (visible && active && quote.state === "idle") beeperData?.ensureQuote(messageID); }
  function forceLayout() { quoteColumn.forceLayout(); }
  onMessageIDChanged: Qt.callLater(resolve)
  onQuoteChanged: Qt.callLater(resolve)
  onActiveChanged: Qt.callLater(resolve)
  Component.onCompleted: Qt.callLater(resolve)
  Rectangle { width: 3; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } color: root.accent; radius: 2 }
  Column {
    id: quoteColumn
    x: 12; y: 8; width: Math.max(0, parent.width - 24); spacing: 3
    Text {
      id: authorLabel
      objectName: "beeperQuoteAuthor"
      width: parent.width; text: root.author; textFormat: Text.PlainText; elide: Text.ElideRight
      color: root.accent
      font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary * root.textScale; weight: Font.DemiBold }
    }
    Text {
      id: previewLabel
      objectName: "beeperQuoteText"
      width: parent.width; text: root.preview; textFormat: Text.PlainText
      wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
      color: Theme.secondary
      font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary * root.textScale }
    }
  }
}
