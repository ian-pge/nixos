import test from 'node:test';
import assert from 'node:assert/strict';
import {cushionProfile} from '../src/cushion.ts';
import {dimensions, PRESETS, sampleSurface, boundaryPoint} from '../src/profile.ts';
import {pebbleContour, pointOnContour} from '../src/pebble.ts';
import {makeGlass, WORLD_SCALE} from '../src/geometry.ts';

const near = (a: number, b: number, tolerance = 1e-6) => assert.ok(Math.abs(a - b) <= tolerance, `${a} != ${b}`);
const shapes = [...Object.values(PRESETS), {...PRESETS.launcher, radius: 1}, {...PRESETS.launcher, radius: 2},
  {width: 800, height: 36, radius: 1}, {width: 80, height: 650, radius: 40},
  {width: 200, height: 200, radius: 100}];

test('cushion preserves the exact footprint and peak, including tiny corner radii', () => {
  for (const shape of shapes) {
    const profile = cushionProfile(shape), peak = dimensions(shape).centreHeight;
    near(profile.height(0), peak); near(profile.height(1), 0);
    for (let i = 0; i < 160; i++) {
      const angle = 2 * Math.PI * i / 160;
      const p = profile.point(1, angle), b = boundaryPoint(angle, shape);
      near(p[0], b[0]); near(p[1], b[1]);
      for (const r of [0, .2, .6, .85, .97, .999]) {
        const [x, y] = profile.point(r, angle), reflected = profile.point(r, angle + Math.PI);
        assert.ok(Number.isFinite(x) && Number.isFinite(y));
        assert.ok(sampleSurface(x, y, shape).distance >= -1e-6, 'no spill outside the real widget');
        near(reflected[0], -x); near(reflected[1], -y);
      }
    }
    near(profile.sectionHeight(0), peak);
    near(profile.sectionHeight(shape.width / 2), 0);
    for (const r of [.1, .4, .8, .95, .999]) {
      const [x] = profile.point(r, 0);
      near(profile.sectionHeight(x), profile.height(r), 1e-5);
    }
  }
});

test('the interior has no folds or reversing sections, even near narrow corners', () => {
  for (const shape of shapes) {
    const profile = cushionProfile(shape), eps = 1e-5;
    for (const r of [.02, .2, .4, .6, .8, .95, .98, .995, .9995]) {
      for (let i = 0; i < 96; i++) {
        const angle = 2 * Math.PI * i / 96;
        const a = profile.point(r - eps, angle), b = profile.point(r + eps, angle);
        const c = profile.point(r, angle - eps), d = profile.point(r, angle + eps);
        const determinant = (b[0] - a[0]) * (d[1] - c[1]) - (b[1] - a[1]) * (d[0] - c[0]);
        assert.ok(determinant > 0, `fold at ${JSON.stringify(shape)}, r=${r}, angle=${angle}`);
      }
    }
  }
});

function curvature(point: (angle: number) => [number, number], angle: number) {
  const e = .0002, a = point(angle - e), p = point(angle), b = point(angle + e);
  const dx = (b[0] - a[0]) / (2 * e), dy = (b[1] - a[1]) / (2 * e);
  const ddx = (a[0] - 2 * p[0] + b[0]) / (e * e), ddy = (a[1] - 2 * p[1] + b[1]) / (e * e);
  return (dx * ddy - dy * ddx) / Math.hypot(dx, dy) ** 3;
}

test('geometry spreads the upper corner curvature, not just the lighting or normals', () => {
  for (const radius of [1, 2, 18]) {
    const shape = {...PRESETS.launcher, radius}, profile = cushionProfile(shape);
    for (const height of [.6, .8]) {
      const rho = Math.sqrt(1 - height * height), previous = pebbleContour(1 - rho, shape);
      const current: number[] = [], before: number[] = [];
      for (let i = 0; i <= 256; i++) {
        const angle = i * Math.PI / 512;
        current.push(curvature(t => profile.point(rho, t), angle));
        before.push(curvature(t => pointOnContour(t, previous), angle));
      }
      assert.ok(current.every(k => Number.isFinite(k) && k > 0));
      assert.ok(Math.max(...current) < Math.max(...before) * .55,
        'reduce the peak curvature of the actual contour by at least 45%');
    }
  }
});

test('mesh, section and summit agree; selection never alters positions', () => {
  const shape = {...PRESETS.launcher, radius: 2}, rings = 32, sectors = 96, scale = .08;
  const plain = makeGlass(shape, scale, 'cushion', false, rings, sectors);
  const selected = makeGlass(shape, scale, 'cushion', true, rings, sectors);
  const profile = cushionProfile(shape), pos = plain.surface.getAttribute('position');
  assert.deepEqual(pos.array, selected.surface.getAttribute('position').array);
  assert.equal(pos.count, 1 + rings * sectors);
  for (let r = 1; r <= rings; r++) {
    const rho = 1 - (1 - r / rings) ** 2;
    for (let i = 0; i < sectors; i++) {
      const index = 1 + (r - 1) * sectors + i;
      const [x, y] = profile.point(rho, 2 * Math.PI * i / sectors);
      near(pos.getX(index), x * WORLD_SCALE);
      near(pos.getZ(index), y * WORLD_SCALE);
      near(pos.getY(index), profile.height(rho) * scale * WORLD_SCALE);
    }
  }
  const normals = plain.surface.getAttribute('normal');
  for (let i = 0; i < normals.count; i++) {
    near(Math.hypot(normals.getX(i), normals.getY(i), normals.getZ(i)), 1, 1e-5);
    assert.ok(normals.getY(i) >= 0, 'no inverted top faces');
  }
  const section = plain.section.getAttribute('position');
  for (let i = 1; i < section.count; i += 2)
    near(section.getY(i), profile.sectionHeight(section.getX(i) / WORLD_SCALE) * scale * WORLD_SCALE, 2e-5);
  for (const model of [plain, selected]) for (const geometry of Object.values(model)) geometry.dispose();
});

test('the circular case has circular sections, without spurious lobes or a central tip', () => {
  const profile = cushionProfile({width: 200, height: 200, radius: 100});
  for (const rho of [.01, .3, .9, .999]) for (let i = 0; i < 64; i++) {
    const angle = 2 * Math.PI * i / 64, [x, y] = profile.point(rho, angle);
    near(x, 100 * rho * Math.cos(angle)); near(y, 100 * rho * Math.sin(angle));
  }
});
