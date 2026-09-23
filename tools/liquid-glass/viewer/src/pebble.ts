/** Approved pebble model, ported to the compositor's cached GPU field.
 * Construct horizontal, nested contours with an exact rounded-rectangle rim
 * and smooth convex interior. All points on a contour have the same height.
 */
import {clamp, dimensions, type Shape} from './profile.ts';

export interface Contour { hx: number; hy: number; radius: number; rounding?: number }
const smootherstep = (t: number) => t * t * t * (10 + t * (-15 + 6 * t));

export function pebbleRimWidth(shape: Shape) {
  const {hx, hy, radius} = dimensions(shape);
  // Stay outside the medial-axis singularities of the rounded-rectangle SDF.
  return Math.min(radius * 0.4, Math.min(hx, hy) * 0.12);
}

export function pebbleContour(level: number, shape: Shape): Contour {
  const u = clamp(level, 0, 1), {hx, hy, radius} = dimensions(shape);
  const shortest = Math.min(hx, hy), rim = pebbleRimWidth(shape), start = rim / shortest;
  if (u <= start) return {hx: hx - shortest * u, hy: hy - shortest * u, radius: radius - shortest * u};
  const v = (u - start) / (1 - start), blend = clamp(smootherstep(v), 0, 1);
  // Equal physical insets at the rim; increasingly circular contours at the
  // centre. Both half-extents shrink to zero, so there is no flat medial ridge.
  const a = shortest * (1 - u) + (hx - shortest) * (1 - blend);
  const b = shortest * (1 - u) + (hy - shortest) * (1 - blend);
  const remaining = radius - rim;
  const t = shortest * (u - start) / Math.max(remaining, 0.25);
  // Matches radius - inset through its second derivative at the join, but
  // never collapses to a sharp internal corner. The centre tends to a circle.
  const softRadius = remaining / (1 + t + t * t);
  const r = (1 - blend) ** 2 * softRadius + blend * Math.min(a, b);
  const safeRadius = clamp(r, 0, Math.min(a, b));
  const ax = a - safeRadius, by = b - safeRadius;
  const ratio = Math.max(ax, by) > 0 ? Math.min(ax, by) / Math.max(ax, by) : 0;
  const desired = 0.45 * blend;
  // Round the *interior* contours continuously, not their normals after the
  // fact. Replace the rectangle's straight segments by two Minkowski-summed
  // ellipses and retain the circular part. Positive ellipse axes guarantee
  // a smooth convex contour. Fade in with zero first/second derivatives.
  const rounding = ratio > 0 && desired > 0 ? desired * ratio / (desired + ratio) : 0;
  return rounding > 0 ? {hx: a, hy: b, radius: safeRadius, rounding}
    : {hx: a, hy: b, radius: safeRadius};
}

export function pebbleHeight(level: number, shape: Shape) {
  const u = clamp(level, 0, 1);
  // Same peak as the current model for an honest shape-only A/B comparison.
  return dimensions(shape).centreHeight * Math.sqrt(u * (2 - u));
}

export function contourDistance(x: number, y: number, c: Contour) {
  if (c.rounding) {
    // Signed radial gap for the smooth interior (not a Euclidean SDF).
    // Only the sign is needed to invert the nested contours. The original
    // exact-distance field remains in use throughout the uniform outer rim.
    const [bx, by] = pointOnContour(Math.atan2(y, x), c);
    return Math.hypot(x, y) - Math.hypot(bx, by);
  }
  const qx = Math.abs(x) - c.hx + c.radius, qy = Math.abs(y) - c.hy + c.radius;
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - c.radius;
}

/** Ellipse axes chosen so the contour keeps EXACTLY its half-width/height. */
function ellipseParts(c: Contour) {
  const e = c.rounding ?? 0, denominator = 1 - e * e;
  return {e, a: (c.hx - c.radius - e * (c.hy - c.radius)) / denominator,
    b: (c.hy - c.radius - e * (c.hx - c.radius)) / denominator};
}

/** Radius of curvature in normal-angle coordinates; positive and continuous
 * for every smooth interior contour. Used by the geometric regression tests.
 */
export function contourCurvatureRadius(normalAngle: number, contour: Contour) {
  const {e, a, b} = ellipseParts(contour);
  if (e === 0) return (a > 0 && Math.abs(Math.cos(normalAngle)) < 1e-12)
    || (b > 0 && Math.abs(Math.sin(normalAngle)) < 1e-12) ? Infinity : contour.radius;
  const c2 = Math.cos(normalAngle) ** 2, s2 = Math.sin(normalAngle) ** 2;
  return contour.radius + a * e * e / (c2 + e * e * s2) ** 1.5
    + b * e * e / (s2 + e * e * c2) ** 1.5;
}

/** Radial intersection. Keep the exact rounded rectangle at the outer rim;
 * smooth interior contours have no straight-to-circular joins at all.
 */
export function pointOnContour(angle: number, contour: Contour): [number, number] {
  const {hx, hy, radius} = contour;
  if (hx <= 0 || hy <= 0) return [0, 0];
  const c = Math.cos(angle), s = Math.sin(angle), cx = Math.abs(c), sy = Math.abs(s);
  if (contour.rounding) {
    if (cx < 1e-14) return [0, Math.sign(s) * hy];
    if (sy < 1e-14) return [Math.sign(c) * hx, 0];
    const {e, a, b} = ellipseParts(contour), e2 = e * e;
    // Solve the normal direction in log(tan(phi)) coordinates. A linear-angle
    // search loses precision when smoothing is tiny near the untouched rim.
    const bound = Math.max(24, -Math.log(e) + 12);
    let lo = -bound, hi = bound, x = 0, y = 0;
    for (let i = 0; i < 44; i++) {
      const middle = (lo + hi) / 2, k = Math.exp(middle), k2 = k * k;
      const u = 1 / Math.sqrt(1 + e2 * k2), v = 1 / Math.sqrt(k2 + e2);
      const circle = radius / Math.sqrt(1 + k2);
      x = a * u + b * e2 * v + circle;
      y = k * (a * e2 * u + b * v + circle);
      if (y * cx > x * sy) hi = middle;
      else lo = middle;
    }
    const radial = x * cx + y * sy;
    return [c * radial, s * radial];
  }
  let t = Math.min(hx / Math.max(cx, 1e-15), hy / Math.max(sy, 1e-15));
  if (t * cx > hx - radius && t * sy > hy - radius) {
    const dot = cx * (hx - radius) + sy * (hy - radius);
    const constant = (hx - radius) ** 2 + (hy - radius) ** 2 - radius ** 2;
    t = dot + Math.sqrt(Math.max(0, dot * dot - constant));
  }
  return [c * t, s * t];
}

/** Invert the nested contours for the section chart and regression tests. */
export function samplePebbleHeight(x: number, y: number, shape: Shape) {
  if (contourDistance(x, y, pebbleContour(0, shape)) > 1e-9) return 0;
  let lo = 0, hi = 1;
  for (let i = 0; i < 40; i++) {
    const middle = (lo + hi) / 2;
    if (contourDistance(x, y, pebbleContour(middle, shape)) <= 0) lo = middle;
    else hi = middle;
  }
  return pebbleHeight(lo, shape);
}
