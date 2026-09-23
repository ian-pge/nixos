import {pathToFileURL} from 'node:url';
import {verifyProfileSources} from './pebble-source-test.mjs';
export const verifyCushionSources=()=>verifyProfileSources('cushion');
if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  verifyCushionSources();
  console.log('PASS: approved cushion, native coefficients, GPU field and material match the audited sources');
}
