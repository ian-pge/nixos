import QtQuick
import "Morph.js" as Morph

// One native transform for every central content. Geometry owns the animation;
// no extra clock or layout reflow is needed for a width-only transition.
Scale {
  required property Item surface
  required property Item content
  readonly property var factors: Morph.contentScale(surface, content)

  origin.x: content.width / 2
  origin.y: content.height / 2
  xScale: factors.x
  yScale: factors.y
}
