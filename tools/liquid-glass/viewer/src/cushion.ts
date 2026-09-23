/** Approved cushion model, ported to the compositor's cached GPU field.
 * A harmonic disk-to-footprint map carries an elliptical cap. Higher angular
 * frequencies of the outline decay toward the summit instead of propagating
 * small corner radii through every horizontal section of the dome.
 */
import {clamp, dimensions, type Shape} from './profile.ts';
import {pointOnContour} from './pebble.ts';

const MODES = 96, BOUNDARY_SAMPLES = 2048;

function buildCushion(shape: Shape) {
  const {hx, hy, radius, centreHeight} = dimensions(shape);
  const outline = {hx, hy, radius};
  const ax = new Float64Array(MODES), by = new Float64Array(MODES);
  // Reflection symmetries leave only odd cosine modes for X and odd sine
  // modes for Y. Integrate the exact rounded rectangle, not a superellipse.
  for (let i = 0; i < BOUNDARY_SAMPLES; i++) {
    const angle = 2 * Math.PI * i / BOUNDARY_SAMPLES;
    const [x, y] = pointOnContour(angle, outline);
    const c2 = Math.cos(2 * angle), s2 = Math.sin(2 * angle);
    let c = Math.cos(angle), s = Math.sin(angle);
    for (let mode = 0; mode < MODES; mode++) {
      ax[mode] += x * c * 2 / BOUNDARY_SAMPLES;
      by[mode] += y * s * 2 / BOUNDARY_SAMPLES;
      [c, s] = [c * c2 - s * s2, s * c2 + c * s2];
    }
  }

  function point(rho: number, angle: number): [number, number] {
    const r = clamp(rho, 0, 1);
    if (r === 0) return [0, 0];
    const boundary = pointOnContour(angle, outline);
    if (r === 1) return boundary;
    const c2 = Math.cos(2 * angle), s2 = Math.sin(2 * angle), r2 = r * r;
    let c = Math.cos(angle), s = Math.sin(angle), power = r;
    let x = 0, y = 0, bx = 0, bySum = 0;
    for (let mode = 0; mode < MODES; mode++) {
      const px = ax[mode] * c, py = by[mode] * s;
      x += power * px; y += power * py;
      bx += px; bySum += py;
      power *= r2;
      [c, s] = [c * c2 - s * s2, s * c2 + c * s2];
    }
    // Restore the tiny truncated Fourier tail at the exact boundary. The
    // r^193 factor confines it to the rim, with no discrete seam or changed
    // footprint. It is practically zero on the body (r=.8 => ~2e-19).
    return [x + power * (boundary[0] - bx), y + power * (boundary[1] - bySum)];
  }

  const height = (rho: number) => centreHeight * Math.sqrt(Math.max(0, 1 - clamp(rho, 0, 1) ** 2));
  function sectionHeight(x: number) {
    const at = Math.abs(x);
    if (at >= hx) return 0;
    if (at === 0) return centreHeight;
    let lo = 0, hi = 1;
    for (let i = 0; i < 40; i++) {
      const mid = (lo + hi) / 2;
      if (point(mid, 0)[0] < at) lo = mid;
      else hi = mid;
    }
    return height((lo + hi) / 2);
  }
  return {point, height, sectionHeight};
}

// Reuse the coefficients for camera/material/selection changes. This is a
// single bounded CPU cache; it does not add a render loop or GPU pass.
let lastKey = '', lastProfile: ReturnType<typeof buildCushion> | undefined;
export function cushionProfile(shape: Shape) {
  const key = `${shape.width}/${shape.height}/${shape.radius}`;
  if (!lastProfile || key !== lastKey) {
    lastProfile = buildCushion(shape);
    lastKey = key;
  }
  return lastProfile;
}
