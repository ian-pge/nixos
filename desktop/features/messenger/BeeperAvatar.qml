import QtQuick
import Quickshell.Widgets
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Item {
  id: root
  property var chat: null
  property real diameter: 48
  // A growing sidebar avatar keeps one decoded image throughout the animation.
  property int sourceDiameter: Math.ceil(diameter)
  property bool imageEnabled: true
  property bool accentBackground: false
  property bool connectionProblem: false
  readonly property string avatarSource: Format.chatAvatarSource(chat)
  readonly property var network: Format.networkBadge(chat?.network)
  property color accent: [Theme.sideApplications, Theme.sideSystem, Theme.pink, Theme.sideDate][Format.stableHash(chat?.id || Format.chatTitle(chat)) % 4]
  readonly property color effectiveAccent: connectionProblem ? Theme.error : accent
  readonly property bool imageReady: photo.status === Image.Ready
  implicitWidth: diameter
  implicitHeight: diameter

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Qt.alpha(root.accentBackground ? Theme.background : root.effectiveAccent, 0.16)
    antialiasing: true
    Text {
      anchors.centerIn: parent
      text: Format.initials(Format.chatTitle(root.chat))
      textFormat: Text.PlainText
      color: root.accentBackground ? Theme.background : root.effectiveAccent
      font { family: "Ubuntu Nerd Font"; pixelSize: Math.round(root.diameter * 0.35); weight: Font.Medium }
    }
  }

  // Rectangle.clip alone is rectangular: use Quickshell's public rounded clip
  // so the actual photograph, not just its placeholder, has a circular edge.
  ClippingRectangle {
    anchors.fill: parent
    radius: width / 2
    color: "transparent"
    visible: root.imageReady
    Image {
      id: photo
      objectName: "beeperAvatarPhoto"
      anchors.fill: parent
      source: root.imageEnabled ? root.avatarSource : ""
      sourceSize: Qt.size(root.sourceDiameter * 2, root.sourceDiameter * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }
  }

  BeeperNetworkBadge {
    width: Math.round(root.diameter * 0.42)
    network: String(root.chat?.network || "")
    connectionProblem: root.connectionProblem
  }
}
