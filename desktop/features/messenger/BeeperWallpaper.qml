import QtQuick
import Quickshell.Widgets
import "../../ui/Theme.js" as Theme

// One cached SVG tile, shared by all visible tiles. Decorative only: it stays
// behind the whole panel and never takes pointer events or moves with messages.
ClippingRectangle {
  id: root
  enabled: false
  color: "transparent"
  radius: Theme.barSize(18)
  opacity: 0.18
  // Telegram's original 1440 x 2960 artwork, at a readable decorative scale.
  readonly property int tileWidth: 450
  readonly property int tileHeight: 925
  readonly property int columns: Math.ceil(width / tileWidth)
  readonly property int rows: Math.ceil(height / tileHeight)
  Repeater {
    model: root.columns * root.rows
    Image {
      required property int index
      x: (index % root.columns) * root.tileWidth
      y: Math.floor(index / root.columns) * root.tileHeight
      width: root.tileWidth; height: root.tileHeight
      source: "assets/telegram/pattern.svg"
      sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
      smooth: true
    }
  }
}
