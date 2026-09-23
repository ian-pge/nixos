import test from 'node:test';
import assert from 'node:assert/strict';
import {sampleSurface, dimensions, boundaryPoint, PRESETS} from '../src/profile.ts';
import {makeGlass, WORLD_SCALE} from '../src/geometry.ts';

const near = (a: number, b: number, tolerance = 1e-6) => assert.ok(Math.abs(a - b) < tolerance, `${a} != ${b}`);

test('nominal launcher dimensions come from QML, and raw height is not millimetres', () => {
  assert.deepEqual(PRESETS.launcher, {width: 480, height: 398, radius: 18});
  near(dimensions(PRESETS.launcher).centreHeight, 642.0488782051282);
  near(sampleSurface(0, 0, PRESETS.launcher).height, dimensions(PRESETS.launcher).centreHeight, 1e-5);
});

test('boundary, symmetry, and nonnegative finite heights across presets', () => {
  for (const shape of Object.values(PRESETS)) {
    for (let i = 0; i < 128; i++) {
      const [x, y] = boundaryPoint(i * Math.PI * 2 / 128, shape);
      near(sampleSurface(x, y, shape).distance, 0, 1e-6);
      near(sampleSurface(x, y, shape).height, 0, 1e-5);
      for (const rho of [0, 0.3, 0.65, 0.92, 0.99]) {
        const p = sampleSurface(x * rho, y * rho, shape);
        assert.ok(Number.isFinite(p.height) && p.height >= 0);
        near(p.height, sampleSurface(-x * rho, -y * rho, shape).height);
        assert.ok(p.height <= p.centreHeight + 1e-5);
      }
    }
  }
});

test('analytic gradients agree with finite differences', () => {
  for (const shape of Object.values(PRESETS)) {
    for (const join of ['smooth', 'legacy'] as const) {
      for (const [x, y] of [[11, 4], [shape.width / 2 - 3, 2], [10, shape.height / 2 - 7]]) {
        const p = sampleSurface(x, y, shape, join), e = 1e-4;
        near(p.dx, (sampleSurface(x + e, y, shape, join).height - sampleSurface(x - e, y, shape, join).height) / (2 * e), 1e-4);
        near(p.dy, (sampleSurface(x, y + e, shape, join).height - sampleSurface(x, y - e, shape, join).height) / (2 * e), 1e-4);
      }
    }
  }
});

test('new join preserves the body and removes the curvature jump', () => {
  const shape = PRESETS.launcher, d = dimensions(shape), x = d.hx - d.bevelWidth, e = 1e-4;
  const derivative = (at: number, join: 'smooth' | 'legacy') => sampleSurface(at, 0, shape, join).dx;
  const jump = (join: 'smooth' | 'legacy') => Math.abs(
    (derivative(x + e, join) - derivative(x, join)) / e - (derivative(x, join) - derivative(x - e, join)) / e);
  assert.ok(jump('legacy') > 0.1);
  assert.ok(jump('smooth') < 1e-4);
  near(sampleSurface(30, 15, shape, 'smooth').height, sampleSurface(30, 15, shape, 'legacy').height);
});

test('mesh samples exactly this height; selection never adds thickness', () => {
  const shape = PRESETS.launcher, scale = 0.08;
  const plain = makeGlass(shape, scale, 'smooth', false, 24, 64);
  const selected = makeGlass(shape, scale, 'smooth', true, 24, 64);
  const pos = plain.surface.getAttribute('position'), norm = plain.surface.getAttribute('normal');
  assert.deepEqual(pos.array, selected.surface.getAttribute('position').array);
  for (let i = 0; i < pos.count; i++) {
    const p = sampleSurface(pos.getX(i) / WORLD_SCALE, pos.getZ(i) / WORLD_SCALE, shape);
    near(pos.getY(i), p.height * scale * WORLD_SCALE, 2e-5);
    near(Math.hypot(norm.getX(i), norm.getY(i), norm.getZ(i)), 1, 1e-5);
  }
  const ix = plain.surface.index!;
  for (let i = 0; i < ix.count; i += 3) {
    const a = ix.getX(i), b = ix.getX(i + 1), c = ix.getX(i + 2);
    const yNormal = (pos.getZ(b) - pos.getZ(a)) * (pos.getX(c) - pos.getX(a))
      - (pos.getX(b) - pos.getX(a)) * (pos.getZ(c) - pos.getZ(a));
    assert.ok(yNormal > -1e-10, 'top faces must point upward');
  }
  for (const model of [plain, selected]) for (const geometry of Object.values(model)) geometry.dispose();
});

test('narrow capsules and extreme supported proportions stay finite', () => {
  for (const shape of [{width: 80, height: 650, radius: 40}, {width: 800, height: 36, radius: 1}, {width: 80, height: 36, radius: 18}]) {
    const model = makeGlass(shape, 1, 'smooth', false, 16, 48);
    assert.ok([...model.surface.getAttribute('position').array].every(Number.isFinite));
    for (const geometry of Object.values(model)) geometry.dispose();
  }
});
