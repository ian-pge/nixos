import test from 'node:test';
import assert from 'node:assert/strict';
import {dimensions, PRESETS, sampleSurface, boundaryPoint} from '../src/profile.ts';
import {pebbleContour, pebbleHeight, pebbleRimWidth, pointOnContour, contourDistance, contourCurvatureRadius, samplePebbleHeight} from '../src/pebble.ts';
import {makeGlass, WORLD_SCALE} from '../src/geometry.ts';

const near = (a: number, b: number, tolerance = 1e-6) => assert.ok(Math.abs(a - b) <= tolerance, `${a} != ${b}`);
const shapes = [...Object.values(PRESETS), {width: 800, height: 36, radius: 1},
  {width: 80, height: 650, radius: 40}, {width: 200, height: 200, radius: 100}];

test('pebble keeps the exact outer footprint and the same peak for comparison', () => {
  for (const shape of shapes) {
    near(pebbleHeight(0, shape), 0);
    near(pebbleHeight(1, shape), dimensions(shape).centreHeight);
    for (let i = 0; i < 160; i++) {
      const angle = 2 * Math.PI * i / 160;
      const [x, y] = pointOnContour(angle, pebbleContour(0, shape));
      const [bx, by] = boundaryPoint(angle, shape);
      near(x, bx); near(y, by);
    }
  }
});

test('near the rim, equal distance from the edge means equal height INCLUDING corners', () => {
  for (const shape of shapes) {
    const shortest = Math.min(shape.width, shape.height) / 2;
    const inset = pebbleRimWidth(shape) * 0.65, level = inset / shortest;
    const expected = pebbleHeight(level, shape);
    for (let i = 0; i < 80; i++) {
      const [x, y] = pointOnContour(2 * Math.PI * i / 80, pebbleContour(level, shape));
      near(sampleSurface(x, y, shape).distance, inset, 1e-6);
      near(samplePebbleHeight(x, y, shape), expected, 1e-4);
    }
  }
});

test('level contours remain strictly nested and shrink smoothly to one summit', () => {
  for (const shape of shapes) {
    let previous = pebbleContour(0, shape);
    for (let i = 1; i < 200; i++) {
      const c = pebbleContour(i / 200, shape);
      assert.ok(c.radius >= 0 && c.radius <= Math.min(c.hx, c.hy));
      for (let k = 0; k < 48; k++) {
        const [x, y] = pointOnContour(2 * Math.PI * k / 48, c);
        assert.ok(contourDistance(x, y, previous) < 1e-8, 'no crossing or overhang between contours');
      }
      previous = c;
    }
    const tip = pebbleContour(0.999, shape);
    near(tip.hx / tip.hy, 1, 0.001);
    near(tip.radius / Math.min(tip.hx, tip.hy), 1, 0.001);
    assert.deepEqual(pebbleContour(1, shape), {hx: 0, hy: 0, radius: 0});
  }
});

test('the rim-to-body contour join has no slope or curvature jump', () => {
  for (const shape of Object.values(PRESETS)) {
    const start = pebbleRimWidth(shape) / (Math.min(shape.width, shape.height) / 2);
    const e = 1e-6;
    for (const field of ['hx', 'hy', 'radius'] as const) {
      const f = (u: number) => pebbleContour(u, shape)[field];
      const left = (f(start) - f(start - e)) / e;
      const right = (f(start + e) - f(start)) / e;
      near(left, right, 1e-3);
      const curvature = (f(start + e) - 2 * f(start) + f(start - e)) / (e * e);
      near(curvature, 0, 0.3);
    }
  }
});

test('shoulders of the launcher become much more even at the old 18px join', () => {
  const shape = PRESETS.launcher, d = dimensions(shape);
  const points = [[d.hx - 18, 0], [0, d.hy - 18], [d.hx - 18, d.hy - 18]];
  const before = points.map(([x, y]) => sampleSurface(x, y, shape).height);
  const after = points.map(([x, y]) => samplePebbleHeight(x, y, shape));
  assert.ok(Math.max(...before) / Math.min(...before) > 3);
  assert.ok(Math.max(...after) / Math.min(...after) < 1.05, JSON.stringify(after));
});

test('prototype mesh has level rings, finite upward normals, and selection adds no thickness', () => {
  const rings = 24, sectors = 64, shape = PRESETS.launcher;
  const plain = makeGlass(shape, 0.08, 'pebble', false, rings, sectors);
  const selected = makeGlass(shape, 0.08, 'pebble', true, rings, sectors);
  const positions = plain.surface.getAttribute('position'), normals = plain.surface.getAttribute('normal');
  assert.deepEqual(positions.array, selected.surface.getAttribute('position').array);
  for (let r = 1; r <= rings; r++) {
    const level = (1 - r / rings) ** 2;
    for (let i = 0; i < sectors; i++) {
      const vertex = 1 + (r - 1) * sectors + i;
      near(positions.getY(vertex), pebbleHeight(level, shape) * 0.08 * WORLD_SCALE, 1e-6);
      near(Math.hypot(normals.getX(vertex), normals.getY(vertex), normals.getZ(vertex)), 1, 1e-5);
      assert.ok(normals.getY(vertex) >= 0);
    }
  }
  for (const model of [plain, selected]) for (const geometry of Object.values(model)) geometry.dispose();
});

test('the upper contours have continuous nonzero curvature instead of flat/circular joins', () => {
  for (const shape of shapes) {
    for (const level of [0.25, 0.45, 0.65, 0.85]) {
      const c = pebbleContour(level, shape);
      assert.ok((c.rounding ?? 0) > 0);
      for (let i = 0; i <= 360; i++) {
        const angle = i * Math.PI / 180;
        const radius = contourCurvatureRadius(angle, c);
        assert.ok(Number.isFinite(radius) && radius > 0);
        near(1 / radius, 1 / contourCurvatureRadius(angle + Math.PI, c), 1e-7);
      }
      // Bounding dimensions, not an ellipse substituted for the widget.
      near(pointOnContour(0, c)[0], c.hx);
      near(pointOnContour(Math.PI / 2, c)[1], c.hy);
    }
  }
});

test('actual contour geometry removes the old upper-surface curvature jumps', () => {
  const curvature = (c: ReturnType<typeof pebbleContour>, angle: number) => {
    const e = 0.0002, p = pointOnContour(angle, c);
    const a = pointOnContour(angle - e, c), b = pointOnContour(angle + e, c);
    const dx = (b[0] - a[0]) / (2 * e), dy = (b[1] - a[1]) / (2 * e);
    const ddx = (a[0] - 2 * p[0] + b[0]) / (e * e), ddy = (a[1] - 2 * p[1] + b[1]) / (e * e);
    return Math.abs(dx * ddy - dy * ddx) / Math.hypot(dx, dy) ** 3;
  };
  for (const level of [0.35, 0.6, 0.85]) {
    const c = pebbleContour(level, PRESETS.launcher), before = {...c, rounding: 0};
    for (const angle of [Math.atan2(c.hy - c.radius, c.hx), Math.atan2(c.hy, c.hx - c.radius)]) {
      const jump = (contour: typeof c) => Math.abs(curvature(contour, angle + 0.002) - curvature(contour, angle - 0.002));
      assert.ok(jump(c) < jump(before) * 0.12, 'remove the jump by moving vertices, not by changing lighting');
      const oldPoint = pointOnContour(angle, before), newPoint = pointOnContour(angle, c);
      assert.ok(Math.hypot(oldPoint[0] - newPoint[0], oldPoint[1] - newPoint[1]) > 0.001);
    }
  }
});
