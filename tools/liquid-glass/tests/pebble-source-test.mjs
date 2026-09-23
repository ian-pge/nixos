// Fail closed if either side of the reviewed viewer/GPU port changes without
// updating its parity tests and audit. No generation or source writes here.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

export function verifyProfileSources(name) {
  const manifest=JSON.parse(readFileSync(new URL('../'+name+'-source.json',import.meta.url),'utf8'));
  for(const [file,expected] of Object.entries(manifest.sources)) {
    const source=readFileSync(new URL('../'+file,import.meta.url),'utf8');
    const normalized=source.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\n]*/g,'').replace(/\s+/g,'');
    const actual=createHash('sha256').update(normalized).digest('hex');
    if(actual!==expected) throw new Error('Le profil '+name+' a changé ('+file+'). Revalider la parité GPU/visualiseur avant de renouveler '+name+'-source.json.');
  }
  return true;
}
export const verifyPebbleSources=()=>verifyProfileSources('pebble');
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  verifyPebbleSources();
  console.log('PASS: approved pebble model, GPU field and material sampling match the audited sources');
}
