pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Local.LiquidGlass
import "../ui"
import "../ui/Theme.js" as Theme
import "../features/calendar/Calendar.js" as Calendar

Item {
  id: root
  required property var controller
  property bool forceHovered: false
  property bool attachedToTop: true
  property bool attachedToBottom: false
  readonly property bool edgeAttached: attachedToTop || attachedToBottom
  readonly property real corner: Math.min(Theme.barSize(18), height / 2)
  readonly property color accent: Theme.electricCyan
  readonly property bool hovered: forceHovered || pointer.containsMouse
  readonly property string dateText: controller.today.toLocaleDateString(Qt.locale("fr_FR"), "dddd").slice(0, 2)
    + " " + controller.today.toLocaleDateString(Qt.locale("fr_FR"), "d MMM")
  readonly property var forecast: controller.weather.days[Calendar.dateKey(controller.today)]
  readonly property string weatherIcon: Calendar.weatherIcon(forecast?.code)
  signal clicked()

  // Share the upper widgets' height and curvature, leaving room for the
  // concave shoulders around the centered clock and its two side readings.
  implicitWidth: Math.max(Theme.barSize(243.2), information.width + 2 * corner + Theme.barSize(19.2))
  implicitHeight: Theme.barGroupHeight
  Accessible.role: Accessible.Button
  Accessible.name: dateText + ", " + controller.timeText + ", " + controller.weather.temperatureText
  Accessible.description: "Open calendar and weather"
  Accessible.onPressAction: root.clicked()

  // Mirror only the backdrop for the bottom edge; text stays upright.
  // Concave shoulders join the screen edge with the rounded inner corners.
  Shape {
    anchors.fill: parent
    visible: root.edgeAttached
    transform: Scale {
      origin.y: root.height / 2
      yScale: root.attachedToBottom ? -1 : 1
    }
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: "transparent"
      strokeWidth: 0
      fillColor: "#000000"
      startX: 0; startY: 0
      PathLine { x: root.width; y: 0 }
      PathCubic { x: root.width - root.corner; y: root.corner; control1X: root.width - 0.5523 * root.corner; control1Y: 0; control2X: root.width - root.corner; control2Y: 0.4477 * root.corner }
      PathLine { x: root.width - root.corner; y: root.height - root.corner }
      PathCubic { x: root.width - 2 * root.corner; y: root.height; control1X: root.width - root.corner; control1Y: root.height - 0.4477 * root.corner; control2X: root.width - 1.4477 * root.corner; control2Y: root.height }
      PathLine { x: 2 * root.corner; y: root.height }
      PathCubic { x: root.corner; y: root.height - root.corner; control1X: 1.4477 * root.corner; control1Y: root.height; control2X: root.corner; control2Y: root.height - 0.4477 * root.corner }
      PathLine { x: root.corner; y: root.corner }
      PathCubic { x: 0; y: 0; control1X: root.corner; control1Y: 0.4477 * root.corner; control2X: 0.5523 * root.corner; control2Y: 0 }
    }
  }
  Rectangle {
    anchors.fill: parent
    visible: !root.edgeAttached
    radius: height / 2
    color: "#000000"
  }
  // Extend the glass body beyond the attached screen edge.
  GlassShape {
    x: root.edgeAttached ? root.corner : 0
    y: root.attachedToTop && !root.attachedToBottom ? -root.corner : 0
    width: root.width - (root.edgeAttached ? 2 * root.corner : 0)
    height: root.height + (root.edgeAttached ? root.corner : 0)
    radius: root.edgeAttached ? root.corner : root.height / 2
    enabled: GlassState.enabled
  }
  component Cell: Row {
    property string text: ""
    property string iconName: ""
    // Design units, scaled with the rest of the bar (not fixed output pixels).
    property int textSize: Theme.barSize(11.2)
    spacing: Theme.barSize(4)
    Icon {
      objectName: "notchIcon"
      visible: parent.iconName !== ""
      name: parent.iconName; size: Theme.barSize(13.6); color: root.accent
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      objectName: "notchLabel"
      text: parent.text
      color: root.hovered ? Theme.selectedForeground : Theme.foreground
      font.family: "Ubuntu"
      font.pixelSize: parent.textSize
      Behavior on color { ColorAnimation { duration: 160 } }
    }
  }
  Item {
    id: information
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    readonly property real sideWidth: Math.max(dateCell.implicitWidth, weatherCell.implicitWidth)
    width: 2 * sideWidth + Theme.barSize(20.8) + timePill.width
    height: timePill.height
    Item {
      width: information.sideWidth; height: parent.height
      Cell {
        id: dateCell
        objectName: "datePill"
        text: root.dateText
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
      }
    }
    Rectangle {
      id: timePill
      objectName: "timePill"
      x: (parent.width - width) / 2
      width: Math.max(Theme.barSize(52.8), timeLabel.implicitWidth + Theme.barSize(12.8))
      height: Theme.barSize(19.2); radius: height / 2
      color: root.accent
      Text {
        id: timeLabel
        objectName: "notchLabel"
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        text: root.controller.timeText
        color: "#000000"
        font.family: "Ubuntu"
        font.pixelSize: Theme.barSize(14.4); font.bold: true
        textFormat: Text.PlainText
      }
    }
    Item {
      x: timePill.x + timePill.width + Theme.barSize(20.8) / 2
      width: information.sideWidth; height: parent.height
      Cell {
        id: weatherCell
        objectName: "weatherPill"
        text: root.controller.weather.temperatureText
        textSize: Theme.barSize(12); iconName: root.weatherIcon
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
      }
    }
  }
  MouseArea {
    id: pointer
    objectName: "calendarNotchPointer"
    x: root.edgeAttached ? root.corner : 0
    width: root.width - 2 * x; height: root.height
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
