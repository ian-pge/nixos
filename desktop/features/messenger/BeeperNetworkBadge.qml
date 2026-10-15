import QtQuick
import QtQuick.Controls
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

// The messaging network over the bottom-right edge of a photo: chat list,
// conversation header and message notifications draw the same badge.
Rectangle {
  id: root
  // Beeper's network name, e.g. "Instagram"; empty hides the badge.
  property string network: ""
  property bool connectionProblem: false
  property bool showsName: true
  readonly property var service: Format.networkBadge(network)
  readonly property color glyphColor: connectionProblem || Theme.beeperNetworkColors[service.key]
    ? Theme.background : Theme.selectedForeground

  objectName: "beeperNetworkBadge"
  width: Math.round(parent.width * 0.42)
  height: width
  x: parent.width - width + 2
  y: parent.height - height + 2
  radius: width / 2
  visible: service.name !== ""
  color: connectionProblem ? Theme.error : Theme.beeperNetworkColors[service.key] || Theme.surfaceRaised
  antialiasing: true
  Accessible.role: Accessible.StaticText
  Accessible.name: service.name + (connectionProblem ? ": connection problem" : "")

  Text {
    anchors.centerIn: parent
    visible: !root.service.iconName
    text: root.service.glyph
    textFormat: Text.PlainText
    color: root.glyphColor
    font { family: "Ubuntu Nerd Font"; pixelSize: Math.round(root.width * 0.60); bold: !root.service.logo }
  }
  Icon {
    anchors.centerIn: parent
    name: root.service.iconName || ""; visible: name !== ""
    size: Math.round(root.width * 0.60)
    color: root.glyphColor
  }
  HoverHandler { id: hover; enabled: root.showsName }
  ToolTip {
    visible: hover.hovered; text: root.service.name; delay: 350
    palette.toolTipText: Theme.foreground
    background: Rectangle { radius: 8; color: Theme.surfaceRaised }
  }
}
