pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../../ui/Theme.js" as Theme
import "Storage.js" as Storage

Item {
  id: root
  required property var rows
  required property var colors
  readonly property real measuredBytes: Storage.sum(rows)
  readonly property bool hasMeasurements: rows.some(row => Storage.known(row.bytes))
  readonly property var segments: Storage.segments(rows)
  property bool loading: false
  implicitWidth: 146
  implicitHeight: 146
  readonly property real diameter: Math.min(width, height)
  readonly property real ringWidth: 20
  readonly property real ringRadius: Math.max(0, (diameter - ringWidth) / 2)
  Accessible.role: Accessible.Chart
  Accessible.name: measuredBytes > 0 ? "Répartition de " + Storage.formatBytes(measuredBytes)
    : loading ? "Mesure en cours" : "Aucune répartition disponible"

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: "transparent"
      strokeColor: Theme.surfaceRaised
      strokeWidth: root.ringWidth
      PathAngleArc {
        centerX: root.width / 2; centerY: root.height / 2
        radiusX: root.ringRadius; radiusY: root.ringRadius
        startAngle: -90; sweepAngle: 360
      }
    }
  }
  Repeater {
    model: root.segments
    delegate: Shape {
      id: slice
      required property var modelData
      objectName: "storageSlice_" + modelData.id
      readonly property real sweepAngle: modelData.sweepAngle
      anchors.fill: parent
      visible: sweepAngle > 0
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.colors[slice.modelData.id] || Theme.inactive
        strokeWidth: root.ringWidth
        capStyle: ShapePath.FlatCap
        PathAngleArc {
          centerX: root.width / 2; centerY: root.height / 2
          radiusX: root.ringRadius; radiusY: root.ringRadius
          startAngle: slice.modelData.startAngle
          sweepAngle: slice.sweepAngle
        }
      }
    }
  }
  Text {
    objectName: "storageChartTotal"
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.height / 2 - 18
    width: Math.max(0, root.diameter - 2 * root.ringWidth - 8)
    text: root.hasMeasurements ? Storage.formatBytes(root.measuredBytes) : "—"
    color: Theme.foreground
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 17; font.bold: true
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
  }
  Text {
    objectName: "storageChartCaption"
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.height / 2 + 5
    text: root.hasMeasurements ? "mesurés" : root.loading ? "Mesure…" : "Sans données"
    color: Theme.secondary
    font.family: "Ubuntu Nerd Font"
    font.pixelSize: 10
    textFormat: Text.PlainText
  }
}
