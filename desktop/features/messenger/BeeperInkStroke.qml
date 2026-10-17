import QtQuick
import QtQuick.Shapes

// Keep finished geometry in the scene graph. Only the last short path changes
// on pointer movement; no image-sized raster buffer is repainted or uploaded.
Shape {
  id: root
  objectName: "beeperInkStroke"
  required property color color
  required property real relativeWidth
  property var chunks: []
  property int pointCount: 0
  property point firstPoint: Qt.point(0, 0)
  readonly property int chunkLimit: 48
  anchors.fill: parent
  preferredRendererType: Shape.CurveRenderer
  asynchronous: false

  function append(point) {
    if (!pointCount) firstPoint = Qt.point(point.x, point.y);
    const previous = chunks.length ? chunks[chunks.length - 1] : null;
    if (!previous || previous.points.length >= chunkLimit) {
      const path = chunkComponent.createObject(root, {
        points: previous ? [previous.points[previous.points.length - 1], point] : [point]
      });
      root.data.push(path);
      chunks = chunks.concat([path]);
    } else previous.points = previous.points.concat([point]);
    ++pointCount;
  }
  Rectangle {
    visible: root.pointCount === 1
    x: root.firstPoint.x * root.width - width / 2
    y: root.firstPoint.y * root.height - height / 2
    width: root.relativeWidth * root.width; height: width; radius: width / 2
    color: root.color; antialiasing: true
  }
  Component {
    id: chunkComponent
    ShapePath {
      id: segment
      property var points: []
      strokeColor: root.color
      strokeWidth: root.relativeWidth * root.width
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: (points[0]?.x || 0) * root.width
      startY: (points[0]?.y || 0) * root.height
      PathPolyline { path: segment.points.map(point => Qt.point(point.x * root.width, point.y * root.height)) }
    }
  }
}
