import QtQuick
import QtQuick.Shapes
import Quickshell.Hyprland
import Local.LiquidGlass
import "../ui"
import "../ui/Theme.js" as Theme
import "../ui/Morph.js" as Morph
import "../features/assistant"

// The black bottom notch: date, time and weather at rest, the Qwen chat when
// open. One surface owns the geometry and grows upward from the screen edge,
// with the central capsule's motion: OutCubic size, crossfaded contents, and
// MorphScale on each axis. Its concave shoulders stay joined to the edge.
Item {
  id: root
  objectName: "bottomNotch"
  required property var calendar
  required property var assistant
  required property var panelWindow
  required property string monitorName
  property bool windowFocused: false
  property bool calendarOpen: false
  // Space for the open notch below the top bar; set by the bar.
  property real availableWidth: 1600
  property real availableHeight: 900
  readonly property bool active: assistant.visible && assistant.targetMonitor === monitorName && !assistant.blocked
  readonly property bool presented: active || expansion > 0
  readonly property bool wantsKeyboard: active && (!assistant.passive || panel.showingCorrection)
  readonly property bool chatFocused: panel.activeFocus
  readonly property real compactWidth: calendarContent.implicitWidth
  readonly property real compactHeight: Theme.barGroupHeight
  readonly property real openCorner: Theme.barSize(18)
  readonly property real panelWidth: Math.max(0, Math.min(960, availableWidth - 54))
  // Reports use their content's natural height. Long reports and the chat
  // stop at the messenger's top edge; the bottom stays on the screen edge.
  readonly property real maximumPanelHeight: Math.max(0, availableHeight - 10 - 50)
  readonly property real panelHeight: panel.showingCorrection
    ? Math.min(maximumPanelHeight, Math.max(compactHeight, Math.ceil(panel.correctionHeight)))
    : maximumPanelHeight
  readonly property real targetWidth: active ? panelWidth + 2 * openCorner : compactWidth
  readonly property real targetHeight: active ? panelHeight : compactHeight
  readonly property real corner: Math.min(Theme.barSize(18), height / 2)
  // Elapsed-time progress for the fades; geometry uses its own Behavior.
  property real expansion: 0
  property real fadeProgress: 1
  property real calendarStart: 1
  property real panelStart: 0
  readonly property real calendarOpacity: active ? Morph.outgoing(calendarStart, fadeProgress) : Morph.incoming(calendarStart, fadeProgress)
  readonly property real panelOpacity: active ? Morph.incoming(panelStart, fadeProgress) : Morph.outgoing(panelStart, fadeProgress)
  signal calendarRequested()
  signal returnFocusRequested()

  property real animatedWidth: targetWidth
  property real animatedHeight: targetHeight
  width: animatedWidth
  height: animatedHeight
  Behavior on animatedWidth { NumberAnimation { duration: Morph.duration; easing.type: Easing.OutCubic } }
  Behavior on animatedHeight { NumberAnimation { duration: Morph.duration; easing.type: Easing.OutCubic } }

  // An interruption resumes from the opacities currently displayed.
  onActiveChanged: {
    const calendarNow = calendarOpacity, panelNow = panelOpacity;
    fades.stop();
    calendarStart = calendarNow; panelStart = panelNow;
    fadeProgress = 0;
    fades.start();
    expansionAnimation.to = active ? 1 : 0;
    expansionAnimation.restart();
    if (active) Qt.callLater(focusPanel);
    else { const hadFocus = focusGrab.active; focusGrab.active = false; if (hadFocus) Qt.callLater(() => root.returnFocusRequested()); }
  }
  NumberAnimation { id: fades; target: root; property: "fadeProgress"; from: 0; to: 1; duration: Morph.duration; easing.type: Easing.Linear }
  NumberAnimation { id: expansionAnimation; target: root; property: "expansion"; duration: Morph.duration }

  HyprlandFocusGrab {
    id: focusGrab
    windows: [root.panelWindow]
    // Never bind active to visibility: clicking another app must release it.
  }
  function focusPanel() {
    if (!active || assistant.passive) return;
    focusGrab.active = true;
    panel.forceActiveFocus();
    panel.compose();
  }
  Connections {
    target: root.assistant
    function onFocusSerialChanged() { Qt.callLater(root.focusPanel); }
    function onBlockedChanged() { if (root.assistant.blocked) focusGrab.active = false; }
  }

  // Mirrored from the top notch: the screen edge is at the bottom.
  Shape {
    anchors.fill: parent
    transform: Scale { origin.y: root.height / 2; yScale: -1 }
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
  // Extend the glass body beyond the screen edge.
  GlassShape {
    x: root.corner
    width: root.width - 2 * root.corner
    height: root.height + root.corner
    radius: root.corner
    enabled: GlassState.enabled
  }
  CalendarNotch {
    id: calendarContent
    objectName: "calendarNotch"
    drawBackground: false
    attachedToTop: false
    attachedToBottom: true
    controller: root.calendar
    forceHovered: root.calendarOpen
    // Lay out at the compact size and follow the surface with MorphScale.
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    width: root.compactWidth
    height: root.compactHeight
    transform: MorphScale { surface: root; content: calendarContent }
    opacity: root.calendarOpacity
    visible: opacity > 0.001
    enabled: !root.active
    onClicked: root.calendarRequested()
    onSecondaryClicked: root.assistant.show(root.monitorName)
  }
  Item {
    id: body
    x: root.corner
    width: root.width - 2 * root.corner
    height: root.height
    clip: true
    AssistantPanel {
      id: panel
      objectName: "assistantPanel"
      // The final layout never follows the animated edges.
      x: (body.width - width) / 2
      y: (body.height - height) / 2
      width: root.panelWidth
      height: root.panelHeight
      transform: MorphScale { surface: body; content: panel }
      opacity: root.panelOpacity
      visible: opacity > 0.001
      enabled: root.active
      assistantData: root.assistant.assistantData
      active: root.active
      passive: root.assistant.passive
      windowFocused: root.windowFocused && panel.activeFocus
      onCloseRequested: root.assistant.hide()
    }
  }
}
