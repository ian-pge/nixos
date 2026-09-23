import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkShader} from '../scripts/check-shader.mjs';

const source = readFileSync(new URL('../../shaders/previous.frag', import.meta.url), 'utf8');
test('shader provenance accepts the current profile, including whitespace changes', () => {
  assert.equal(checkShader(source), checkShader(source.replaceAll('    ', '  ')));
});
test('shader provenance rejects a modified curvature without touching the real shader', () => {
  assert.throws(() => checkShader(source.replace('48.0 + 2.0', '49.0 + 2.0')), /profil GLSL a changé/);
});
