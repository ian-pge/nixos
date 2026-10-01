import QtQuick
import QtQuick.Shapes
import QtQuick.Controls as Controls
import Local.LiquidGlass
import "../ui"
import "../ui/Theme.js" as Theme

// The filled portion starts at noon and grows clockwise with the value.
Item {
  id: root
  property string iconName: ""
  property url logoSource: ""
  property string badgeText: ""
  property string label: ""
  property var value: null
  property color accent: Theme.foreground
  property bool interactive: false
  property bool forceHovered: false
  property bool muted: false
  property bool charging: false
  readonly property bool known: typeof value === "number" && isFinite(value)
  readonly property real fraction: known ? Math.max(0, Math.min(100, value)) / 100 : 0
  readonly property string tooltipText: known ? Math.round(value) + "%" : "—"
  property string accessibleText: label + " · "
    + (known ? Math.round(value) + "%" : "Unavailable")
    + (charging ? " · Charging" : muted ? " · Muted" : "")
  readonly property color indicatorColor: known && !muted ? accent : Theme.inactive
  property real displayedFraction: fraction
  Behavior on displayedFraction {
    enabled: root.known
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  implicitWidth: Theme.barSize(32)
  implicitHeight: Theme.barSize(32)
  Accessible.role: interactive ? Accessible.Button : Accessible.Indicator
  Accessible.name: accessibleText
  signal leftClicked()
  signal rightClicked()
  signal wheelUp()
  signal wheelDown()

  Rectangle {
    objectName: "dialHighlight"
    anchors.fill: parent
    radius: width / 2
    color: root.forceHovered || (root.interactive && pointer.containsMouse)
      ? Qt.alpha(root.accent, Theme.barSelectionOpacity) : "transparent"
    Behavior on color { ColorAnimation { duration: 160 } }
  }
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: "transparent"
      strokeColor: Qt.alpha(root.indicatorColor, 0.24)
      strokeWidth: 2 * Theme.barScale
      strokeStyle: root.known ? ShapePath.SolidLine : ShapePath.DashLine
      dashPattern: [1, 2]
      PathAngleArc {
        centerX: root.width / 2; centerY: root.height / 2
        radiusX: 13 * Theme.barScale; radiusY: 13 * Theme.barScale
        startAngle: -90; sweepAngle: 360
      }
    }
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.known && root.displayedFraction > 0 ? root.indicatorColor : "transparent"
      strokeWidth: 2 * Theme.barScale
      capStyle: ShapePath.FlatCap
      PathAngleArc {
        objectName: "dialLevelArc"
        centerX: root.width / 2; centerY: root.height / 2
        radiusX: 13 * Theme.barScale; radiusY: 13 * Theme.barScale
        startAngle: -90
        sweepAngle: 360 * root.displayedFraction
      }
    }
  }
  Icon {
    objectName: "dialIcon"
    x: (root.width - width) / 2
    y: (root.height - height) / 2 - (root.badgeText !== "" ? Theme.barSize(3) : 0)
    visible: root.logoSource.toString() === ""
    name: root.iconName
    color: root.charging ? root.accent : root.indicatorColor
    size: Theme.barIconSize
  }
  Image {
    objectName: "dialLogo"
    x: (root.width - width) / 2
    y: (root.height - height) / 2 - (root.badgeText !== "" ? Theme.barSize(3) : 0)
    visible: root.logoSource.toString() !== ""
    width: Theme.barIconSize; height: width
    source: root.logoSource
    sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    opacity: root.known ? 1 : 0.5
  }
  Text {
    objectName: "dialBadge"
    anchors.horizontalCenter: parent.horizontalCenter
    y: Theme.barSize(20)
    visible: root.badgeText !== ""
    text: root.badgeText
    color: root.indicatorColor
    font.family: "Ubuntu"
    font.pixelSize: Theme.barSize(8)
    font.bold: true
  }
  MouseArea {
    id: pointer
    objectName: "dialPointer"
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: root.interactive ? Qt.LeftButton | Qt.RightButton : Qt.NoButton
    cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) root.rightClicked();
      else root.leftClicked();
    }
    onWheel: wheel => {
      if (!root.interactive) { wheel.accepted = false; return; }
      if (wheel.angleDelta.y > 0) root.wheelUp();
      else if (wheel.angleDelta.y < 0) root.wheelDown();
    }
  }
  Controls.ToolTip {
    objectName: "dialTooltip"
    parent: root
    visible: pointer.containsMouse
    delay: 400
    y: root.height + 8
    text: root.tooltipText
    contentItem: Text {
      text: root.tooltipText
      color: Theme.foreground
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: Theme.barSize(13)
    }
    background: Rectangle {
      color: Theme.surfaceRaised; radius: 8
      // The compositor only paints registered glass regions on this surface.
      // ToolTip lives outside the bar's capsules, so it needs its own region.
      GlassShape {
        objectName: "dialTooltipGlassShape"
        anchors.fill: parent; radius: parent.radius
        enabled: GlassState.enabled
      }
    }
  }
}
