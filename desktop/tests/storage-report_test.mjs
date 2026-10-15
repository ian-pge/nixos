import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL('../features/storage/StorageReport.js', import.meta.url), 'utf8')
  .replace(/^\.pragma library\s*/, ''), context);
const now = Date.now();
const report = () => ({schemaVersion: 2, measuredAt: now, estimated: true,
  disk: {totalBytes: 100, usedBytes: 60, availableBytes: 35},
  categories: ['docker', 'nix', 'applications', 'personal', 'vm', 'other'].map(id => ({
    id, bytes: 20, partial: false, ...(id === 'applications' ? {cacheBytes: 5, dataBytes: 15} : {}),
    ...(id === 'docker' ? {breakdown: ['layers', 'volumes', 'buildCache', 'containers', 'other']
      .map(id => ({id, bytes: 4, partial: false}))} : {}),
    ...(id === 'personal' ? {largestEntries: [{path: '~/Projects', bytes: 15, kind: 'directory', partial: false}]} : {})
  }))});
const parse = value => context.parse(JSON.stringify(value), now);
assert.equal(parse(report()).categories.length, 6, 'Btrfs estimates may legitimately exceed physical used');
for (const mutate of [r => r.schemaVersion = 1, r => r.measuredAt += 120000,
  r => r.disk.totalBytes = 0, r => r.disk.usedBytes = -1,
  r => r.categories[1].id = 'docker', r => r.categories.pop(),
  r => r.categories[0].bytes = '10', r => r.categories[0].bytes = -1,
  r => r.categories[0].bytes = 1e30, r => r.categories[0].partial = 'false',
  r => delete r.categories[2].cacheBytes,
  r => delete r.categories[0].breakdown, r => r.categories[0].breakdown.pop(),
  r => r.categories[0].breakdown[1].id = 'layers',
  r => r.categories[0].breakdown[0].bytes = 40,
  r => r.categories[0].breakdown[0].partial = 'false',
  r => delete r.categories[3].largestEntries,
  r => r.categories[3].largestEntries[0].path = '/root/private',
  r => r.categories[3].largestEntries[0].path = '~/../root/private',
  r => r.categories[3].largestEntries[0].path = '~/bad\nname',
  r => r.categories[3].largestEntries[0].bytes = -1,
  r => r.categories[3].largestEntries[0].bytes = 21,
  r => r.categories[3].largestEntries[0].kind = 'unknown',
  r => r.categories[3].largestEntries.push({...r.categories[3].largestEntries[0]}),
  r => r.categories[3].largestEntries.push({path: '~/Projects/child', bytes: 1, kind: 'file', partial: false}),
  r => r.categories[3].largestEntries.push({path: '~/file', bytes: 10, kind: 'file', partial: false}),
  r => r.categories[3].largestEntries.push({path: '~/bigger', bytes: 16, kind: 'file', partial: false}),
  r => r.categories[3].largestEntries = Array.from({length: 6}, (_, i) => ({path: '~/file' + i, bytes: 1, kind: 'file', partial: false}))]) {
  const value = report(); mutate(value); assert.throws(() => parse(value));
}
const partial = report(); partial.categories[0].bytes = null; partial.categories[0].partial = true;
assert.equal(parse(partial).categories[0].bytes, null);
const unknown = report(); unknown.categories[0].breakdown[0] = {id: 'layers', bytes: null, partial: true};
assert.equal(parse(unknown).categories[0].breakdown[0].bytes, null);
console.log('PASS: storage schema, unknown values, duplicate categories and independent physical totals');
