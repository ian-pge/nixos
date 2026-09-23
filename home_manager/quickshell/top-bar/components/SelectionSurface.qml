import QtQuick
import "Theme.js" as Theme

// A tint on the existing glass, never another refractive surface. Keep the
// opaque fallback legible when the compositor material is unavailable.
Rectangle {
  id: root
  property bool selected: false
  property color accent: Theme.foreground
  property real tintOpacity: 0.20
  property color idleColor: "transparent"
  property color fallbackColor: Theme.surfaceRaised

  radius: 10
  border.width: 0
  color: selected
    ? (GlassState.enabled ? Qt.alpha(accent, tintOpacity) : fallbackColor)
    : idleColor
  Behavior on color {
    ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
  }
}
