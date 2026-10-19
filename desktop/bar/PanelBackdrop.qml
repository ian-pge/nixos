import QtQuick
import Quickshell
import "../ui/Morph.js" as Morph

// Visual only: the Bar's input mask deliberately excludes this rectangle.
Rectangle {
  id: root
  property bool shown: false
  // Yield immediately when the compositor owns the backdrop.
  // A fading-out rectangle must not double its dimming.
  property bool suppressed: false
  property bool targetVisible: false
  // Coordinator and messenger ownership can change in the same event turn.
  // Animate only the final state, not a transient panel-to-chat gap.
  function syncTarget() { targetVisible = shown; }
  onShownChanged: Qt.callLater(syncTarget)
  Component.onCompleted: syncTarget()
  readonly property real dimAmount: {
    const configured = Quickshell.env("QS_PANEL_DIM_AMOUNT") ?? "";
    const amount = Number(configured);
    return configured !== "" && isFinite(amount) && amount >= 0 && amount <= 1
      ? amount : 0.6;
  }

  // Dim the wallpaper behind the bar too. Only the actual foreground widgets
  // are exempt, through stacking; leaving a clear strip creates a hard seam.
  anchors.fill: parent
  color: "black"
  opacity: targetVisible ? dimAmount : 0
  visible: !suppressed && opacity > 0
  enabled: false
  Behavior on opacity { NumberAnimation { duration: Morph.duration; easing.type: Easing.OutCubic } }
}
