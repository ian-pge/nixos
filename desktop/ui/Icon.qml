import QtQuick
import "./Theme.js" as Theme
import "./icons/Lucide.js" as Lucide

// Shared offline Lucide renderer. Keep a fixed box while changing icon/state.
// SVGs are rasterized/cached by Qt; no per-icon shader or font is required.
Item {
  id: root
  property string name: ""
  property real size: 18
  property color color: Theme.foreground
  property real strokeWidth: 2
  property bool spinning: false
  readonly property bool valid: !name || Lucide.has(name)
  readonly property alias status: picture.status
  implicitWidth: size
  implicitHeight: size
  onNameChanged: if (!valid) console.warn("Unknown Lucide icon:", name)
  Image {
    id: picture
    anchors.centerIn: parent
    width: Math.max(0, Math.min(root.size, root.width, root.height))
    height: width
    source: Lucide.source(root.name, root.color, root.strokeWidth)
    sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
    fillMode: Image.PreserveAspectFit
    smooth: true
    NumberAnimation on rotation {
      from: 0; to: 360; duration: 900; loops: Animation.Infinite
      running: root.spinning && root.visible && root.name !== ""
      onRunningChanged: if (!running) picture.rotation = 0
    }
  }
}
