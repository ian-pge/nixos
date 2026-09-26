import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Item {
  id: root
  property var chat: null
  property int diameter: 48
  property bool imageEnabled: true
  property bool accentBackground: false
  property bool connectionProblem: false
  readonly property string avatarSource: Format.chatAvatarSource(chat)
  readonly property var network: Format.networkBadge(chat?.network)
  property color accent: [Theme.sideApplications, Theme.sideSystem, Theme.sideWeather, Theme.sideDate][Format.stableHash(chat?.id || Format.chatTitle(chat)) % 4]
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
      anchors.fill: parent
      source: root.imageEnabled ? root.avatarSource : ""
      sourceSize: Qt.size(root.diameter * 2, root.diameter * 2)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }
  }

  Rectangle {
    id: badge
    objectName: "beeperNetworkBadge"
    width: Math.round(root.diameter * 0.42)
    height: width
    x: parent.width - width + 2
    y: parent.height - height + 2
    radius: width / 2
    visible: root.network.name !== ""
    color: root.connectionProblem ? Theme.error : Theme.beeperNetworkColors[root.network.key] || Theme.surfaceRaised
    antialiasing: true
    Accessible.role: Accessible.StaticText
    Accessible.name: root.network.name + (root.connectionProblem ? ": connection problem" : "")
    Text {
      anchors.centerIn: parent
      text: root.network.glyph
      textFormat: Text.PlainText
      color: root.connectionProblem || Theme.beeperNetworkColors[root.network.key] ? Theme.background : Theme.selectedForeground
      font { family: "Ubuntu Nerd Font"; pixelSize: Math.round(badge.width * 0.60); bold: !root.network.logo }
    }
    HoverHandler { id: badgeHover }
    ToolTip {
      visible: badgeHover.hovered; text: root.network.name; delay: 350
      palette.toolTipText: Theme.foreground
      background: Rectangle { radius: 8; color: Theme.surfaceRaised }
    }
  }
}
