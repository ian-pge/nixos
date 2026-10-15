import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../features/storage/Storage.js', import.meta.url), 'utf8')
  .replace(/^\.pragma library\s*/u, '');
const storage = vm.createContext({});
vm.runInContext(source, storage);
const gib = 1073741824;
const snapshot = {disk: {usedBytes: 10 * gib}, categories: [
  {id: 'docker', bytes: 30 * gib, breakdown: ['layers', 'volumes', 'buildCache', 'containers', 'other']
    .map((id, index) => ({id, bytes: [15, 10, 3, 1, 1][index] * gib, partial: false}))}, {id: 'nix', bytes: 10 * gib},
  {id: 'applications', bytes: 20 * gib, cacheBytes: 7 * gib, dataBytes: 13 * gib},
  {id: 'personal', bytes: 40 * gib, largestEntries: ['Projects', 'Downloads', 'Videos', 'Documents', 'archive.tar']
    .map((name, index) => ({path: '~/' + name, bytes: [15, 10, 8, 5, 2][index] * gib,
      kind: index === 4 ? 'file' : 'directory', partial: false}))}, {id: 'vm', bytes: 0}, {id: 'other', bytes: 0}
]};
const rows = storage.rows(snapshot);
assert.equal(rows.length, 6);
assert.equal(storage.sum(rows), 100 * gib);
assert.equal(storage.incomplete(rows), false);
assert.equal(rows[2].cacheBytes, 7 * gib);
assert.equal(rows[0].details.length, 5);
assert.equal(rows[0].details[0].label, 'Images et couches');
assert.equal(rows[0].details.reduce((sum, detail) => sum + detail.bytes, 0), rows[0].bytes);
assert.equal(rows[3].largestEntries.length, 5);
assert.equal(rows[3].largestEntries[0].path, '~/Projects');
for (let i = 1; i < rows.length; ++i) assert.equal(rows[i].y, rows[i - 1].y + rows[i - 1].height);
const segments = storage.segments(rows);
assert.equal(segments[0].startAngle, -90);
assert.equal(segments[0].sweepAngle, 108);
assert.equal(segments[1].startAngle, 18);
assert.equal(segments[4].sweepAngle, 0);
assert.equal(segments.reduce((sum, segment) => sum + segment.sweepAngle, 0), 360);
assert.equal(storage.percent(rows[0].bytes, storage.sum(rows)), '30 %');

const missing = storage.rows(null);
assert.equal(missing.length, 6);
assert.equal(missing[0].bytes, null);
assert.ok(missing[0].details.every(detail => detail.bytes === null));
assert.equal(missing[3].largestEntries.length, 0);
assert.equal(storage.incomplete(missing), true);
assert.ok(storage.segments(missing).every(segment => segment.sweepAngle === 0));
assert.equal(storage.formatBytes(null), '—');
assert.equal(storage.formatBytes(NaN), '—');
assert.equal(storage.formatBytes(-1), '—');
assert.equal(storage.formatBytes(0), '0 Gio');
assert.equal(storage.formatBytes(1), '< 0,1 Gio');
assert.equal(storage.formatBytes(1.5 * gib), '1,5 Gio');
assert.equal(storage.formatEntryBytes(8192), '8,0 Kio');
assert.equal(storage.formatEntryBytes(1048576), '1,0 Mio');
assert.equal(storage.formatEntryBytes(null), '—');
assert.equal(storage.formatEntryBytes(0), '0 o');
assert.equal(storage.percent(null, 100), '—');
assert.equal(storage.percent(0, 0), '—');
assert.equal(storage.percent(1, 1000), '< 1 %');

const zeros = storage.rows({categories: rows.map(row => ({...row, bytes: 0}))});
assert.equal(storage.sum(zeros), 0);
assert.equal(storage.incomplete(zeros), false);
assert.ok(storage.segments(zeros).every(segment => segment.sweepAngle === 0));
const partial = storage.rows({categories: [{id: 'docker', bytes: 5 * gib, partial: true}]});
assert.equal(storage.incomplete(partial), true);
assert.equal(partial[0].bytes, 5 * gib);
assert.equal(partial[1].bytes, null);
assert.equal(storage.timestamp(100000, 100000), 'À l’instant');
assert.equal(storage.timestamp(100000, 220000), 'Il y a 2 min');
assert.equal(storage.timestamp(0, 100000), 'Aucune mesure');
console.log('PASS: storage category proportions, shared-file oversum, missing/zero/partial readings and formatting');
