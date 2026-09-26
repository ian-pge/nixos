import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Item {
  id: root
  required property var message
  property var beeperData: null
  property bool selected: false
  property bool playbackEnabled: true
  property bool renderMedia: true
  property bool viewportReady: true
  property real textScale: 1
  property color networkAccent: Theme.secondary
  property string searchQuery: ""
  readonly property string plainBody: Format.text(message)
  readonly property string highlightedBody: renderMedia ? Format.highlightText(plainBody, searchQuery, Theme.sideBrightness, Theme.background) : ""
  readonly property bool outgoing: !!message.isSender
  readonly property var sender: Format.senderProfile(message, beeperData?.currentChat, beeperData?.accounts)
  readonly property var readers: beeperData?.readReceiptReaders?.[message.id]
    ?? Format.messageReaders(message, beeperData?.currentChat, beeperData?.accounts)
  readonly property string readReceipt: Format.readersLabel(readers)
  readonly property var reactionPeople: Format.messageReactions(message, beeperData?.currentChat, beeperData?.accounts)
  readonly property bool groupMessage: beeperData?.currentChat?.type === "group"
  readonly property color senderColor: groupMessage
    ? (beeperData.senderColors[Format.senderKey(message)] || Theme.sideApplications)
    : Theme.sideApplications
  readonly property color bubbleColor: outgoing ? networkAccent : Theme.surface
  readonly property color contentAccent: outgoing ? Theme.background : senderColor
  readonly property real preferredContentWidth: {
    let widest = Math.max(body.implicitWidth, senderLabel.implicitWidth, metadata.implicitWidth,
      root.message.linkedMessageID ? replyQuote.implicitWidth : 0);
    // Use intrinsic sizes, never the width assigned by this bubble. children
    // also tracks Repeater insertions/removals and late image dimensions.
    for (const child of bubble.children) {
      if (child.objectName === "beeperMedia" || child.objectName === "beeperMessageLink")
        widest = Math.max(widest, child.implicitWidth);
    }
    return widest;
  }
  signal selectedRequested()
  signal previewRequested(var attachment)
  function activateMedia() {
    for (let i = 0; i < attachments.count; ++i) {
      const media = attachments.itemAt(i);
      if (media?.kind === "audio") { media.togglePlayback(); return; }
      if (media?.kind === "image" || media?.kind === "gif" || media?.kind === "video") {
        const attachment = media.kind === "video" && media.sourceReady
          ? Object.assign({}, media.attachment, {srcURL: media.sourceUrl}) : media.attachment;
        previewRequested(attachment); return;
      }
    }
  }
  function forceMessageLayout() {
    replyQuote.forceLayout(); metadata.forceLayout(); bubble.forceLayout(); readerAvatars.forceLayout(); contents.forceLayout();
  }
  implicitHeight: contents.implicitHeight + 4
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton; onClicked: root.selectedRequested() }
  BeeperAvatar {
    id: avatar
    objectName: "beeperSenderAvatar"
    visible: !root.outgoing
    diameter: 40; width: diameter; height: diameter
    x: 8
    y: contents.y + messageSurface.height - height
    chat: root.sender
    accent: root.senderColor
    imageEnabled: visible && root.renderMedia
  }
  Column {
    id: contents
    // Leave room for the selection dot even beside a maximum-width bubble.
    width: Math.max(0, Math.min(parent.width - (root.outgoing ? 0 : avatar.width) - 42, 680))
    x: root.outgoing ? root.width - width - 14 : avatar.width + 22
    y: 2
    spacing: 4
    Item {
      id: messageSurface
      objectName: "beeperMessageBubble"
      width: Math.min(parent.width, Math.max(110, root.preferredContentWidth + 28))
      height: bubble.implicitHeight + 12
      anchors.right: root.outgoing ? parent.right : undefined
      Shape {
        objectName: "beeperMessageShape"
        preferredRendererType: Shape.CurveRenderer
        antialiasing: true
        visible: root.renderMedia
        anchors.fill: parent
        // One continuous filled path avoids alpha seams at the small tail.
        transform: Scale { origin.x: messageSurface.width / 2; xScale: root.outgoing ? -1 : 1 }
        ShapePath {
          strokeWidth: 0; strokeColor: "transparent"; fillColor: root.bubbleColor
          startX: 18; startY: 0
          PathLine { x: messageSurface.width - 18; y: 0 }
          PathQuad { x: messageSurface.width; y: 18; controlX: messageSurface.width; controlY: 0 }
          PathLine { x: messageSurface.width; y: messageSurface.height - 18 }
          PathQuad { x: messageSurface.width - 18; y: messageSurface.height; controlX: messageSurface.width; controlY: messageSurface.height }
          PathLine { x: 2; y: messageSurface.height }
          PathCubic { x: -7.5; y: messageSurface.height - 0.5; control1X: -2; control1Y: messageSurface.height; control2X: -6; control2Y: messageSurface.height }
          PathCubic { x: 0; y: messageSurface.height - 14; control1X: -1; control1Y: messageSurface.height - 3; control2X: 0; control2Y: messageSurface.height - 7 }
          PathLine { x: 0; y: 18 }
          PathQuad { x: 18; y: 0; controlX: 0; controlY: 0 }
        }
      }
      Column {
        id: bubble
        width: parent.width - 28
        x: 14; y: 6; spacing: 3
        Text {
          id: senderLabel
          objectName: "beeperSenderName"
          width: parent.width; text: root.sender.title; textFormat: Text.PlainText
          elide: Text.ElideRight; color: root.contentAccent
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label * root.textScale; weight: Font.DemiBold }
        }
        BeeperQuote {
          id: replyQuote
          width: parent.width
          beeperData: root.beeperData
          messageID: root.message.linkedMessageID || ""
          active: root.playbackEnabled && root.renderMedia
          textScale: root.textScale
        }
        Text {
          id: body
          objectName: "messageBody"
          width: parent.width
          visible: !!text
          text: root.plainBody
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.highlightedBody ? "transparent" : root.outgoing ? Theme.background : Theme.foreground
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.body * root.textScale }
          lineHeight: 1.2
          // Plain text always owns the geometry. The optional native rich-text
          // layer paints escaped spans in place, with no layout/scroll changes.
          // Neither item ever switches format while it holds untrusted text.
          Text {
            objectName: "beeperMessageHighlights"
            anchors.fill: parent
            visible: !!root.highlightedBody
            text: root.highlightedBody
            textFormat: Text.RichText
            wrapMode: body.wrapMode
            color: root.outgoing ? Theme.background : Theme.foreground
            font: body.font
          }
        }
        Repeater {
          id: attachments
          model: root.message.attachments || []
          BeeperMedia {
            required property var modelData
            width: bubble.width
            attachment: modelData; beeperData: root.beeperData
            playbackEnabled: root.playbackEnabled
            renderEnabled: root.renderMedia
            accent: root.contentAccent
            accentBackground: root.outgoing
            onPreviewRequested: attachment => root.previewRequested(attachment)
          }
        }
        Repeater {
          model: Format.links(root.message)
          BeeperButton {
            required property var modelData
            objectName: "beeperMessageLink"
            width: bubble.width
            text: "↗  " + (modelData.title || modelData.url)
            font.pixelSize: Theme.beeperFont.control * root.textScale
            prominent: true
            accent: root.outgoing ? root.contentAccent : Theme.sideApplications
            onClicked: Qt.openUrlExternally(modelData.url)
          }
        }
        Item {
          id: metadata
          objectName: "beeperMessageMeta"
          width: parent.width
          readonly property bool hasReactions: root.reactionPeople.length > 0
          readonly property real reactionWidth: {
            let width = 0, count = 0;
            for (const child of reactions.children) {
              if (child.objectName !== "beeperMessageReaction") continue;
              width += child.implicitWidth; ++count;
            }
            return width + Math.max(0, count - 1) * reactions.spacing;
          }
          readonly property real reactionLineHeight: {
            let height = messageDetails.implicitHeight;
            for (const child of reactions.children)
              if (child.objectName === "beeperMessageReaction") height = Math.max(height, child.implicitHeight);
            return height;
          }
          readonly property real widestReaction: {
            let width = 0;
            for (const child of reactions.children)
              if (child.objectName === "beeperMessageReaction") width = Math.max(width, child.implicitWidth);
            return width;
          }
          readonly property bool separateTimeRow: hasReactions && width < widestReaction + messageDetails.implicitWidth + 12
          implicitWidth: messageDetails.implicitWidth + (hasReactions ? reactionWidth + 12 : 0)
          implicitHeight: separateTimeRow ? reactions.implicitHeight + 4 + messageDetails.implicitHeight
            : Math.max(hasReactions ? reactions.implicitHeight : 0, messageDetails.implicitHeight)
          function forceLayout() { messageDetails.forceLayout(); reactions.forceLayout(); }
          Flow {
            id: reactions
            objectName: "beeperMessageReactions"
            visible: metadata.hasReactions
            width: Math.max(0, parent.width - (metadata.separateTimeRow ? 0 : messageDetails.implicitWidth + 12))
            layoutDirection: Qt.LeftToRight
            spacing: 8
            Repeater {
              model: root.reactionPeople
              Rectangle {
                id: reactionChip
                required property var modelData
                objectName: "beeperMessageReaction"
                readonly property string tooltipText: (modelData.person.anonymous ? "Participant unavailable" : modelData.person.title)
                  + " · " + modelData.key + (modelData.count > 1 ? " × " + modelData.count : "")
                implicitWidth: reactionContents.implicitWidth + 12
                implicitHeight: reactionContents.implicitHeight + 8
                width: Math.min(implicitWidth, reactions.width)
                height: metadata.reactionLineHeight
                radius: height / 2
                color: Qt.alpha(root.outgoing ? Theme.background : root.networkAccent, 0.16)
                antialiasing: true
                Accessible.role: Accessible.StaticText
                Accessible.name: tooltipText
                Row {
                  id: reactionContents
                  anchors.centerIn: parent
                  spacing: 5
                  Item {
                    width: 26 * root.textScale
                    height: reactionAvatar.height
                    Text {
                      objectName: "beeperReactionEmoji"
                      anchors.centerIn: parent; width: parent.width
                      visible: reactionImage.status !== Image.Ready
                      text: reactionChip.modelData.key; textFormat: Text.PlainText
                      horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                      color: root.outgoing ? Theme.background : Theme.foreground
                      font { family: "Ubuntu Nerd Font"; pixelSize: 22 * root.textScale }
                    }
                    Image {
                      id: reactionImage
                      objectName: "beeperReactionImage"
                      anchors.fill: parent
                      source: root.renderMedia ? Format.chatAvatarSource({imgURL: reactionChip.modelData.imgURL}) : ""
                      sourceSize: Qt.size(width * 2, height * 2)
                      visible: status === Image.Ready; asynchronous: true; fillMode: Image.PreserveAspectFit
                    }
                  }
                  BeeperAvatar {
                    id: reactionAvatar
                    objectName: "beeperReactionAvatar"
                    diameter: Math.round(26 * root.textScale); width: diameter; height: diameter
                    chat: reactionChip.modelData.person
                    imageEnabled: root.renderMedia
                    accentBackground: root.outgoing
                  }
                  Text {
                    visible: reactionChip.modelData.count > 1
                    anchors.verticalCenter: parent.verticalCenter
                    text: reactionChip.modelData.count; textFormat: Text.PlainText
                    color: root.outgoing ? Theme.background : Theme.foreground
                    font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption * root.textScale }
                  }
                }
                HoverHandler { id: reactionHover }
                ToolTip {
                  visible: reactionHover.hovered; delay: 350
                  text: reactionChip.tooltipText
                  contentItem: Text { text: reactionChip.tooltipText; textFormat: Text.PlainText; color: Theme.foreground; font.pixelSize: Theme.beeperFont.caption }
                  palette.toolTipText: Theme.foreground
                  background: Rectangle { radius: 8; color: Theme.surfaceRaised }
                }
              }
            }
          }
          Row {
            id: messageDetails
            anchors.right: parent.right
            // Align with the last reaction row when a narrow bubble wraps.
            y: metadata.separateTimeRow ? parent.height - height : parent.height - (metadata.reactionLineHeight + height) / 2
            layoutDirection: Qt.RightToLeft
            spacing: 8
            Text {
              objectName: "beeperMessageTime"
              text: Format.time(root.message.timestamp)
              color: root.outgoing ? Theme.background : Theme.inactive
              font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption * root.textScale }
            }
            Text {
              visible: root.outgoing && !!text
              text: root.message.sendStatus?.status === "PENDING" ? "Sending…" : String(root.message.sendStatus?.status || "").startsWith("FAIL") ? "Failed" : ""
              color: Theme.background
              font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption * root.textScale }
            }
          }
        }
      }
      Rectangle {
        objectName: "beeperMessageSelection"
        visible: root.selected
        x: root.outgoing ? -width - 6 : parent.width + 6
        anchors.verticalCenter: parent.verticalCenter
        width: 12; height: 12; radius: width / 2
        color: root.networkAccent
        antialiasing: true
      }
    }
    Flow {
      id: readerAvatars
      objectName: "beeperMessageReadReceipt"
      x: messageSurface.x
      width: messageSurface.width
      visible: root.readers.length > 0
      layoutDirection: root.outgoing ? Qt.RightToLeft : Qt.LeftToRight
      spacing: 4
      Repeater {
        model: root.readers
        BeeperAvatar {
          id: readerAvatar
          required property var modelData
          objectName: "beeperReaderAvatar"
          readonly property string tooltipText: modelData.anonymous ? "Read · reader unavailable" : "Read by " + modelData.title
          diameter: Math.round(22 * root.textScale); width: diameter; height: diameter
          chat: modelData
          imageEnabled: root.renderMedia
          Accessible.role: Accessible.StaticText
          Accessible.name: tooltipText
          HoverHandler { id: readerHover }
          ToolTip {
            visible: readerHover.hovered; delay: 350
            text: readerAvatar.tooltipText
            contentItem: Text { text: readerAvatar.tooltipText; textFormat: Text.PlainText; color: Theme.foreground; font.pixelSize: Theme.beeperFont.caption }
            palette.toolTipText: Theme.foreground
            background: Rectangle { radius: 8; color: Theme.surfaceRaised }
          }
        }
      }
    }
  }
}
