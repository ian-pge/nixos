import QtQuick
import QtQuick.Controls
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Flow {
  id: root
  objectName: "beeperMessageReactions"
  property var people: []
  property string messageIdentity: ""
  property bool renderMedia: true
  property bool outgoing: false
  property real textScale: 1
  property color networkAccent: Theme.secondary
  property real lineHeight: 0
  // Keep existing pills and avatars on refresh, without entry/exit effects.
  readonly property var reactionRows: {
    const occurrences = new Map();
    return (people || []).map(person => {
      const identity = JSON.stringify([messageIdentity, person.person.id, person.key]);
      const occurrence = occurrences.get(identity) || 0;
      occurrences.set(identity, occurrence + 1);
      return {id: JSON.stringify([identity, occurrence]), reaction: person};
    });
  }
  readonly property int count: reactionModel.count
  readonly property real totalWidth: {
    let width = 0, count = 0;
    for (const child of children) {
      if (child.objectName !== "beeperMessageReaction") continue;
      width += child.implicitWidth; ++count;
    }
    return width + Math.max(0, count - 1) * spacing;
  }
  readonly property real tallestChip: {
    let height = 0;
    for (const child of children)
      if (child.objectName === "beeperMessageReaction") height = Math.max(height, child.implicitHeight);
    return height;
  }
  readonly property real widestChip: {
    let width = 0;
    for (const child of children)
      if (child.objectName === "beeperMessageReaction") width = Math.max(width, child.implicitWidth);
    return width;
  }
  layoutDirection: Qt.LeftToRight
  spacing: 8

  KeyedListModel { id: reactionModel; rows: root.reactionRows }
  Repeater {
    model: reactionModel
    Rectangle {
      id: chip
      required property var row
      readonly property var modelData: row.reaction
      objectName: "beeperMessageReaction"
      readonly property string tooltipText: (modelData.person.anonymous ? "Participant unavailable" : modelData.person.title)
        + " · " + modelData.key + (modelData.count > 1 ? " × " + modelData.count : "")
      implicitWidth: reactionContents.implicitWidth + 12
      implicitHeight: reactionContents.implicitHeight + 8
      width: Math.min(implicitWidth, root.width)
      height: Math.max(implicitHeight, root.lineHeight)
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
            text: chip.modelData.key; textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            color: root.outgoing ? Theme.background : Theme.foreground
            font { family: "Ubuntu Nerd Font"; pixelSize: 22 * root.textScale }
          }
          Image {
            id: reactionImage
            objectName: "beeperReactionImage"
            anchors.fill: parent
            source: root.renderMedia ? Format.chatAvatarSource({imgURL: chip.modelData.imgURL}) : ""
            sourceSize: Qt.size(width * 2, height * 2)
            visible: status === Image.Ready; asynchronous: true; fillMode: Image.PreserveAspectFit
          }
        }
        BeeperAvatar {
          id: reactionAvatar
          objectName: "beeperReactionAvatar"
          diameter: Math.round(26 * root.textScale); width: diameter; height: diameter
          chat: chip.modelData.person
          imageEnabled: root.renderMedia
          accentBackground: root.outgoing
        }
        Text {
          visible: chip.modelData.count > 1
          anchors.verticalCenter: parent.verticalCenter
          text: chip.modelData.count; textFormat: Text.PlainText
          color: root.outgoing ? Theme.background : Theme.foreground
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption * root.textScale }
        }
      }
      HoverHandler { id: reactionHover }
      ToolTip {
        visible: reactionHover.hovered; delay: 350
        text: chip.tooltipText
        contentItem: Text { text: chip.tooltipText; textFormat: Text.PlainText; color: Theme.foreground; font.pixelSize: Theme.beeperFont.caption }
        palette.toolTipText: Theme.foreground
        background: Rectangle { radius: 8; color: Theme.surfaceRaised }
      }
    }
  }
}
