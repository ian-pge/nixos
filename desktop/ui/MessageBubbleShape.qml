import QtQuick
import QtQuick.Shapes

// The chat bubble shared by the messenger and the assistant: rounded corners
// and a small tail at the bottom, mirrored for outgoing messages. One
// continuous filled path avoids alpha seams between the tail and the body.
Shape {
  id: root
  property bool outgoing: false
  property color fillColor: "transparent"
  property color strokeColor: "transparent"
  property real strokeWidth: 0
  preferredRendererType: Shape.CurveRenderer
  antialiasing: true
  transform: Scale { origin.x: root.width / 2; xScale: root.outgoing ? -1 : 1 }
  ShapePath {
    strokeWidth: root.strokeWidth; strokeColor: root.strokeColor; fillColor: root.fillColor
    startX: 18; startY: 0
    PathLine { x: root.width - 18; y: 0 }
    PathQuad { x: root.width; y: 18; controlX: root.width; controlY: 0 }
    PathLine { x: root.width; y: root.height - 18 }
    PathQuad { x: root.width - 18; y: root.height; controlX: root.width; controlY: root.height }
    PathLine { x: 2; y: root.height }
    PathCubic { x: -7.5; y: root.height - 0.5; control1X: -2; control1Y: root.height; control2X: -6; control2Y: root.height }
    PathCubic { x: 0; y: root.height - 14; control1X: -1; control1Y: root.height - 3; control2X: 0; control2Y: root.height - 7 }
    PathLine { x: 0; y: 18 }
    PathQuad { x: 18; y: 0; controlX: 0; controlY: 0 }
  }
}
