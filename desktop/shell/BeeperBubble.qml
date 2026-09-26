import QtQuick
import Local.LiquidGlass
import "../ui/Theme.js" as Theme
import "../ui"

// The chat visually grows out of the central capsule, but owns its geometry
// independently so changing a top-bar indicator cannot replace the conversation.
Item {
  id: root
  property bool expanded: false
  property bool animate: true
  property bool glassEnabled: GlassState.enabled
  property real barTop: 10
  property real workAreaTop: 46
  // Match the outer frame of a full-height tiled Hyprland window. These are
  // general.gaps_out.top/bottom from home_manager/hyprland/settings.nix.
  property real windowTopGap: 10
  property real windowBottomGap: 10
  readonly property real panelVerticalMargin: 50
  property real sourceWidth: 434
  property real sourceHeight: 36
  property real capsuleWidth: sourceWidth
  property real capsuleHeight: sourceHeight
  // Animate the actual geometry fraction toward either endpoint. Both opening
  // and closing start quickly and decelerate; a reversal starts at this frame.
  property real progress: 0
  readonly property int animationDuration: 360
  property bool initialized: false
  property bool openingPrepared: false
  property rect fromGeometry: Qt.rect(0, 0, 0, 0)
  property rect toGeometry: Qt.rect(0, 0, 0, 0)
  property real fromProgress: 0
  property real toProgress: 1
  readonly property bool animating: reveal.running
  readonly property real panelWidth: Math.min(1280, Math.max(0, width - 54))
  readonly property real tiledWindowHeight: Math.max(0, height - workAreaTop - windowTopGap - windowBottomGap)
  readonly property real panelHeight: Math.max(0, tiledWindowHeight - panelVerticalMargin * 2)
  readonly property real panelTop: workAreaTop + windowTopGap + (tiledWindowHeight - panelHeight) / 2
  readonly property rect panelGeometry: Qt.rect((width - panelWidth) / 2, panelTop, panelWidth, panelHeight)
  readonly property real geometryFraction: fromProgress === toProgress ? 1
    : Math.max(0, Math.min(1, (progress - fromProgress) / (toProgress - fromProgress)))
  readonly property rect geometry: progress === 1 ? panelGeometry : progress === 0 ? capsuleGeometry()
    : Qt.rect(fromGeometry.x + (toGeometry.x - fromGeometry.x) * geometryFraction,
      fromGeometry.y + (toGeometry.y - fromGeometry.y) * geometryFraction,
      fromGeometry.width + (toGeometry.width - fromGeometry.width) * geometryFraction,
      fromGeometry.height + (toGeometry.height - fromGeometry.height) * geometryFraction)
  readonly property real originContentOpacity: 1 - smooth(0, 0.48, progress)
  readonly property Item surfaceItem: surface
  readonly property Item contentItem: content
  readonly property color surfaceColor: glassEnabled ? Qt.alpha(Theme.background, 0.12) : Theme.background
  visible: expanded || progress > 0
  // Keep the visual subtree enabled through closing: GlassShape's native
  // collector ignores effectively disabled items, including disabled parents.
  // Only interactive content is disabled when the close starts.

  function captureCapsule() {
    capsuleWidth = Math.max(0, Math.min(width, sourceWidth));
    capsuleHeight = Math.max(0, Math.min(height, sourceHeight));
  }
  function capsuleGeometry() { return Qt.rect((width - capsuleWidth) / 2, barTop, capsuleWidth, capsuleHeight); }
  function resetGeometry() {
    fromGeometry = capsuleGeometry(); toGeometry = panelGeometry;
    fromProgress = 0; toProgress = 1;
  }
  function prepareOpen() {
    if (progress === 0) { captureCapsule(); resetGeometry(); }
    openingPrepared = true;
  }
  function transition() {
    if (!initialized) return;
    const start = progress;
    let origin = Qt.rect(surface.x, surface.y, surface.width, surface.height);
    reveal.stop();
    if (expanded && start === 0) {
      if (!openingPrepared) captureCapsule();
      origin = capsuleGeometry();
    } else if (!expanded) captureCapsule();
    openingPrepared = false;
    const destination = expanded ? 1 : 0;
    if (!animate || start === destination) {
      resetGeometry();
      progress = destination;
      return;
    }
    // A new destination (e.g. weather) starts at the exact currently rendered
    // rectangle, including if the previous transformation was interrupted.
    fromGeometry = origin;
    toGeometry = expanded ? panelGeometry : capsuleGeometry();
    fromProgress = start; toProgress = destination;
    reveal.from = start;
    reveal.to = destination;
    reveal.duration = Math.max(1, Math.round(animationDuration * Math.abs(destination - start)));
    reveal.start();
  }
  function retargetClosed() {
    if (!initialized || expanded) return;
    if (progress === 0) { captureCapsule(); resetGeometry(); }
    else if (reveal.running && !reveal.paused) transition();
  }
  onExpandedChanged: transition()
  onSourceWidthChanged: Qt.callLater(retargetClosed)
  onSourceHeightChanged: Qt.callLater(retargetClosed)
  onProgressChanged: if (progress === 0 && !expanded) { captureCapsule(); resetGeometry(); }
  onAnimateChanged: if (initialized && !animate) {
    reveal.stop();
    resetGeometry();
    progress = expanded ? 1 : 0;
  }
  Component.onCompleted: {
    captureCapsule();
    resetGeometry();
    progress = expanded ? 1 : 0;
    initialized = true;
  }

  function smooth(start, end, value) {
    const t = Math.max(0, Math.min(1, (value - start) / (end - start)));
    return t * t * (3 - 2 * t);
  }

  NumberAnimation {
    id: reveal
    objectName: "beeperBubbleReveal"
    target: root
    property: "progress"
    easing.type: Easing.OutCubic
  }

  Rectangle {
    id: surface
    objectName: "beeperBubbleSurface"
    width: root.geometry.width
    height: root.geometry.height
    x: root.geometry.x
    y: root.geometry.y
    radius: 18
    color: root.surfaceColor
    clip: true
    GlassShape {
      objectName: "beeperGlassShape"
      anchors.fill: parent; radius: surface.radius
      enabled: root.glassEnabled && root.visible
    }
    Item {
      id: content
      enabled: root.expanded
      width: root.panelWidth; height: root.panelHeight
      anchors.centerIn: parent
      opacity: root.smooth(0.18, 0.78, root.progress)
    }
  }
}
