// Evaluate the scalar expressions FROM the GLSL so the regression test follows
// the shipped profile, not a second hand-maintained implementation of it.
import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const analytic = readFileSync(new URL('../shaders/previous.frag', import.meta.url), 'utf8');
const raster = readFileSync(new URL('../shaders/glass.frag', import.meta.url), 'utf8');
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
const near = (actual, expected, tolerance, label) =>
    assert.ok(Math.abs(actual - expected) <= tolerance, `${label}: ${actual} != ${expected}`);

function scalar(source, name, args) {
    const expression = source.match(new RegExp('(?:const )?float ' + name + ' = ([^;]+);'))?.[1];
    assert.ok(expression, 'Missing GLSL scalar: ' + name);
    // These local shader expressions use only scalar arithmetic and these
    // numeric functions. Reject other tokens before evaluating them as JS.
    assert.match(expression, /^[\w\s.+*/(),-]+$/);
    for (const token of expression.match(/[A-Za-z_]\w*/g) ?? [])
        assert.ok([...args, 'sqrt', 'max', 'clamp'].includes(token), 'Unexpected token: ' + token);
    const evaluate = new Function(...args, 'sqrt', 'max', 'clamp', 'return ' + expression);
    return (...values) => evaluate(...values, Math.sqrt, Math.max, clamp);
}
const eased = scalar(analytic, 'eased', ['t']);
const easeSlope = scalar(analytic, 'easeSlope', ['t']);
const arc = scalar(analytic, 'arc', ['eased']);
const arcRange = scalar(analytic, 'arcRange', [])();
const bevel = scalar(analytic, 'bevel', ['arc', 'arcRange']);
const bevelSlope = scalar(analytic, 'bevelSlope', ['eased', 'easeSlope', 'bevelWidth', 'arc', 'arcRange']);
function profile(d, width) {
    const t = clamp(d / width, 0, 1), u = eased(t), a = arc(u);
    return [bevel(a, arcRange), bevelSlope(u, easeSlope(t), width, a, arcRange)];
}

// A C1-only circular join used to have this nonzero curvature on the inner
// side, and zero outside. The tests below must reject that old profile.
const oldCurvatureJump = 1 / (Math.sqrt(1.04) * arcRange);
assert.ok(oldCurvatureJump > 1);
for (const width of [0.5, 1, 4, 8.1, 18, 20]) {
    near(profile(0, width)[0], 0, 1e-10, 'outer height');
    near(profile(0, width)[1], 1 / (width * 0.2 * arcRange), 1e-9, 'outer slope unchanged');
    near(profile(width, width)[0], 1, 1e-8, 'inner height');
    near(profile(width, width)[1], 0, 1e-10, 'inner slope');
    let previous = 0;
    for (let i = 1; i <= 1000; ++i) {
        const d = width * i / 1000, [height, slope] = profile(d, width);
        assert.ok(Number.isFinite(height) && Number.isFinite(slope));
        assert.ok(height >= previous - 1e-12 && height <= 1 + 1e-8 && slope >= 0);
        previous = height;
        if (i < 990) {
            const h = width * 1e-6;
            const numerical = (profile(d + h, width)[0] - profile(d - h, width)[0]) / (2 * h);
            near(slope * width, numerical * width, 1e-5, 'gradient matches height');
        }
    }
    const h = width * 1e-4;
    const curvatureInside = (profile(width, width)[1] - profile(width - h, width)[1]) / h;
    near(curvatureInside * width * width, 0, 1e-5, 'continuous curvature at inner join');
    near(profile(width * 2, width)[0], 1, 1e-8, 'body height unchanged');
    near(profile(width * 2, width)[1], 0, 1e-10, 'no rim contribution in body');
}

// The height is bodyHeight * bevel; check the full refracted displacement and
// its derivative at the join, not just the normalized bevel in isolation.
for (const [halfHeight, bodyRadius, centreHeight, width] of [
    [18, 48, 16, 8.1], [199, 48, 650, 18], [220, 68, 824, 18], [400, 48, 3200, 20]]) {
    const bend = d => {
        const p = d - halfHeight;
        const body = Math.max(centreHeight - p * p / (2 * bodyRadius), 0);
        const [b, db] = profile(d, width);
        const slope = (-p / bodyRadius) * b + body * db;
        return 36 * slope / Math.hypot(slope, 1);
    };
    const h = width * 1e-4;
    const left = (bend(width) - bend(width - h)) / h;
    const right = (bend(width + h) - bend(width)) / h;
    near(left, right, 0.002, 'no refraction-derivative kink');
    assert.ok(Math.abs(bend(width * 1.2)) > 1, 'body refraction retained');
}

const rasterEase = scalar(raster, 'eased', ['t']);
const rasterProfile = scalar(raster, 'profile', ['edge']);
for (let i = 0; i <= 100; ++i) near(rasterEase(i / 100), eased(i / 100), 0, 'matching fallback easing');
near(rasterProfile(1), 1, 1e-12, 'fallback rim strength unchanged');
near(rasterProfile(0), 0, 1e-12, 'fallback body unchanged');
near(rasterProfile(1 - rasterEase(0.999)), 0, 1e-9, 'fallback smooth inner join');
console.log('PASS: monotone profile, matching gradient, smooth curvature/refraction join, unchanged body and raster fallback');
