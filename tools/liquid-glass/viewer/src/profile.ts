/** Archived CPU port of previous.frag's height field, NOT a physical volume.
 * check-shader.mjs rejects drift in the GLSL block before dev/build/test.
 * x/y are surface-local logical pixels; the viewer maps height onto world Y.
 */
export type Join = 'smooth' | 'legacy';
export type SurfaceProfile = Join | 'pebble';
export interface Shape { width: number; height: number; radius: number }
export const PRESETS: Record<string, Shape> = {
  launcher: {width: 480, height: 398, radius: 18},
  capsule: {width: 260, height: 36, radius: 18},
  calendar: {width: 434, height: 398, radius: 18},
};
export const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));

export function dimensions(shape: Shape) {
  const hx = Math.max(shape.width / 2, 0.01), hy = Math.max(shape.height / 2, 0.01);
  const shortest = Math.min(hx, hy);
  const radius = clamp(shape.radius, 0, shortest);
  const rx = 48 + 2 * (hx - shortest), ry = 48 + 2 * (hy - shortest);
  const centreHeight = 8 + hx * hx * (0.5 / rx) + hy * hy * (0.5 / ry);
  const bevelWidth = Math.max(Math.min(20, shortest * 0.45, Math.max(radius, 0.5)), 0.5);
  return {hx, hy, radius, rx, ry, centreHeight, bevelWidth};
}

export function sampleSurface(x: number, y: number, shape: Shape, join: Join = 'smooth') {
  const {hx, hy, radius, rx, ry, centreHeight, bevelWidth} = dimensions(shape);
  const qx = Math.abs(x) - hx + radius, qy = Math.abs(y) - hy + radius;
  const ox = Math.max(qx, 0), oy = Math.max(qy, 0), len = Math.hypot(ox, oy);
  const distance = radius - len - Math.min(Math.max(qx, qy), 0);
  const outward = len > 0.00001
    ? [Math.sign(x) * ox / len, Math.sign(y) * oy / len]
    : qx > qy ? [Math.sign(x), 0] : [0, Math.sign(y)];
  const t = clamp(Math.max(distance, 0) / bevelWidth, 0, 1);
  const eased = join === 'smooth' ? t * (1 + t * (1 - t)) : t;
  const easeSlope = join === 'smooth' ? (1 - t) * (1 + 3 * t) : 1;
  const arc = Math.sqrt(0.04 + eased * (2 - eased)), arcRange = 0.819803903;
  const bevel = (arc - 0.2) / arcRange;
  const db = (1 - eased) * easeSlope / (bevelWidth * arc * arcRange);
  const bodyHeight = Math.max(centreHeight - x * x * (0.5 / rx) - y * y * (0.5 / ry), 0);
  const height = bodyHeight * bevel;
  const dx = (-x / rx) * bevel - bodyHeight * db * outward[0];
  const dy = (-y / ry) * bevel - bodyHeight * db * outward[1];
  return {height, dx, dy, distance, bevelWidth, centreHeight};
}

/** Unique radial intersection with the convex rounded-rectangle footprint. */
export function boundaryPoint(angle: number, shape: Shape): [number, number] {
  const c = Math.cos(angle), s = Math.sin(angle);
  let lo = 0, hi = Math.hypot(shape.width, shape.height);
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    if (sampleSurface(c * mid, s * mid, shape).distance >= 0) lo = mid;
    else hi = mid;
  }
  return [c * lo, s * lo];
}
