import QtQuick
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./AssistantFormat.js" as Format

// One conversation bubble, in the messenger's visual language. Both roles use
// the backend's HTML in one selectable rich-text view: Markdown for Qwen,
// escaped literal text for the user's own messages.
Item {
  id: root
  required property var message
  property var mathRenderer: null
  property bool selected: false
  property real textScale: 1
  property real baseSize: 18
  property color accent: Theme.flamingo
  property string assistantName: "Qwen"
  property url logo: Qt.resolvedUrl("assets/qwen/logo.png")
  property string searchQuery: ""
  property bool currentMatch: false
  property real arrivalProgress: 1
  readonly property bool outgoing: !!message.isSender
  readonly property bool streaming: message.state === "generating"
  // The agent works but no reply text streams yet: before the first word and
  // during tool calls. The avatar breathes and the label shimmers; no ring.
  readonly property bool thinking: !outgoing && streaming && message.thinking === true
  // An empty reply only shows the thinking label, not the "…" placeholder.
  readonly property bool waitingOnly: thinking && (message.text || "") === "…"
  property real thinkingTime: 0
  FrameAnimation { running: root.thinking && root.visible; onTriggered: root.thinkingTime += frameTime }
  onThinkingChanged: if (!thinking) thinkingTime = 0
  readonly property string selectedText: body.copyText
  readonly property var links: outgoing ? [] : Format.links(message.html)
  signal selectedRequested()
  signal textSelectionStarted()
  signal openRequested(string url)
  function clearTextSelection() { body.clearTextSelection(); }
  function playArrival() { arrival.stop(); arrivalProgress = 0; arrival.start(); }
  implicitHeight: column.implicitHeight + 4
  opacity: arrivalProgress
  transform: Translate { y: (1 - root.arrivalProgress) * 8 }
  NumberAnimation { id: arrival; target: root; property: "arrivalProgress"; to: 1; duration: 140; easing.type: Easing.OutCubic }

  MouseArea { anchors.fill: parent; onClicked: root.selectedRequested() }
  Rectangle {
    id: avatar
    objectName: "assistantAvatar"
    visible: !root.outgoing
    width: Math.round(36 * Math.min(1.2, root.textScale)); height: width; radius: width / 2
    x: 12
    y: column.y + bubble.height - height
    color: "#ffffff"
    antialiasing: true
    scale: root.thinking ? 1 + 0.06 * Math.sin(root.thinkingTime * Math.PI * 1.25) : 1
    Image {
      anchors { fill: parent; margins: parent.width * 0.14 }
      source: root.logo
      sourceSize: Qt.size(parent.width * 2, parent.width * 2)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }
  }
  Column {
    id: column
    width: Math.max(0, Math.min(parent.width - (root.outgoing ? 0 : avatar.width + 8) - 34, root.outgoing ? 640 : 760))
    x: root.outgoing ? root.width - width - 10 : avatar.x + avatar.width + 14
    y: 2
    Item {
      id: bubble
      objectName: "assistantBubble"
      width: Math.min(parent.width, Math.max(96, Math.max(root.waitingOnly ? 0 : body.implicitWidth, header.implicitWidth,
        root.thinking ? thinkingLabel.implicitWidth : 0) + 28))
      height: header.height + (root.waitingOnly ? 0 : body.height) + (root.thinking ? thinkingLabel.height + 6 : 0) + 18
      anchors.right: root.outgoing ? parent.right : undefined
      MessageBubbleShape {
        objectName: "assistantBubbleShape"
        anchors.fill: parent
        outgoing: root.outgoing
        fillColor: root.outgoing ? root.accent : Theme.surface
        strokeWidth: root.currentMatch ? 2 : 0
        strokeColor: root.currentMatch ? Theme.yellow : "transparent"
      }
      Item {
        id: header
        x: 14; y: 7
        width: bubble.width - 28
        implicitWidth: name.implicitWidth + 12 + time.implicitWidth
        height: Math.max(name.implicitHeight, time.implicitHeight)
        Text {
          id: name
          text: root.outgoing ? "You" : root.assistantName
          textFormat: Text.PlainText
          color: root.outgoing ? Theme.background : root.accent
          font { family: "Ubuntu Nerd Font"; pixelSize: root.baseSize * 0.85 * root.textScale; weight: Font.DemiBold }
        }
        Text {
          id: time
          objectName: "assistantMessageTime"
          anchors.right: parent.right
          anchors.verticalCenter: name.verticalCenter
          text: root.thinking ? "" : root.streaming ? "Writing…" : Format.time(root.message.timestamp)
          textFormat: Text.PlainText
          color: root.outgoing ? Theme.background : Theme.inactive
          font { family: "Ubuntu Nerd Font"; pixelSize: root.baseSize * 0.7 * root.textScale }
        }
      }
      AssistantMarkdown {
        id: body
        objectName: "assistantMessageBody"
        x: 14; y: header.y + header.height + 2
        width: bubble.width - 28
        height: implicitHeight
        visible: !root.waitingOnly
        html: root.message.html || ""
        mathRenderer: root.outgoing ? null : root.mathRenderer
        searchQuery: root.searchQuery
        textScale: root.textScale
        baseSize: root.baseSize
        accent: root.outgoing ? Theme.background : root.accent
        textColor: root.outgoing ? Theme.background : Theme.foreground
        selectedTextColor: root.outgoing ? root.accent : Theme.background
        onSelectedRequested: root.selectedRequested()
        onTextSelectionStarted: root.textSelectionStarted()
        onOpenRequested: url => root.openRequested(url)
      }
      AssistantThinking {
        id: thinkingLabel
        x: 14
        y: header.y + header.height + (root.waitingOnly ? 4 : body.height + 8)
        visible: root.thinking
        accent: root.accent
        pixelSize: root.baseSize * 0.9 * root.textScale
      }
      Rectangle {
        objectName: "assistantMessageSelection"
        visible: root.selected
        x: root.outgoing ? -width - 6 : parent.width + 6
        anchors.verticalCenter: parent.verticalCenter
        width: 12; height: 12; radius: 6
        color: root.accent
      }
    }
  }
}
