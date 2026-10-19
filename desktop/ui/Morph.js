.pragma library

// One motion language for every central widget, including the messenger.
var duration = 220;
var minScale = 0.5;
var maxScale = 2;

function clamp(value) {
  return Math.max(0, Math.min(1, value));
}

function smooth(start, end, value) {
  const t = clamp((value - start) / (end - start));
  return t * t * (3 - 2 * t);
}

function elapsed(travel) {
  return 1 - Math.pow(1 - clamp(travel), 1 / 3);
}

function easeOut(time) {
  return 1 - Math.pow(1 - clamp(time), 3);
}

function incoming(startOpacity, time) {
  return startOpacity + (1 - startOpacity) * smooth(0.18, 0.78, time);
}

function outgoing(startOpacity, time) {
  return startOpacity * (1 - smooth(0, 0.32, time));
}

// Bound each axis independently relative to the content's normal size.
// At the minimum, the surface's existing clip masks any content that extends
// beyond its animated edges. The two axes do not constrain each other.
function axisScale(surfaceExtent, contentExtent) {
  return Math.max(minScale, Math.min(maxScale,
    surfaceExtent / Math.max(1, contentExtent)));
}

function contentScale(surface, content) {
  return {x: axisScale(surface.width, content.width),
    y: axisScale(surface.height, content.height)};
}
