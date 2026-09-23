import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {verifyPebbleSources} from '../../tests/pebble-source-test.mjs';
import {verifyCushionSources} from '../../tests/cushion-source-test.mjs';

export function checkShader(source = readFileSync(new URL('../../shaders/previous.frag', import.meta.url), 'utf8')) {
  verifyPebbleSources();
  verifyCushionSources();
  const expected = JSON.parse(readFileSync(new URL('../src/profile-source.json', import.meta.url), 'utf8'));
  const start = source.search(/\bvec2\s+halfSize\s*=/), end = source.search(/\bvec3\s+normal\s*=/);
  if (start < 0 || end <= start) throw new Error('Champ de hauteur GLSL introuvable.');
  const block = source.slice(start, end).replace(/\/\/[^\n]*/g, '').replace(/\s+/g, '');
  const hash = createHash('sha256').update(block).digest('hex');
  if (hash !== expected.sha256)
    throw new Error('Le profil GLSL a changé : mettre à jour profile.ts et ses tests avant de renouveler son empreinte.');
  return hash;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  console.log('PASS: coussin GPU et profils précédents archivés vérifiés (' + checkShader().slice(0, 12) + ')');
