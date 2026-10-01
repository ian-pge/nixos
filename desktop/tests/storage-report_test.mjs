import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL('../features/storage/StorageReport.js', import.meta.url), 'utf8')
  .replace(/^\.pragma library\s*/, ''), context);
const now = Date.now();
const report = () => ({schemaVersion: 1, measuredAt: now, estimated: true,
  disk: {totalBytes: 100, usedBytes: 60, availableBytes: 35},
  categories: ['docker', 'nix', 'applications', 'personal', 'vm', 'other'].map(id => ({
    id, bytes: 20, partial: false, ...(id === 'applications' ? {cacheBytes: 5, dataBytes: 15} : {})
  }))});
const parse = value => context.parse(JSON.stringify(value), now);
assert.equal(parse(report()).categories.length, 6, 'Btrfs estimates may legitimately exceed physical used');
for (const mutate of [r => r.schemaVersion = 2, r => r.measuredAt += 120000,
  r => r.disk.totalBytes = 0, r => r.disk.usedBytes = -1,
  r => r.categories[1].id = 'docker', r => r.categories.pop(),
  r => r.categories[0].bytes = '10', r => r.categories[0].bytes = -1,
  r => r.categories[0].bytes = 1e30, r => r.categories[0].partial = 'false',
  r => delete r.categories[2].cacheBytes]) {
  const value = report(); mutate(value); assert.throws(() => parse(value));
}
const partial = report(); partial.categories[0].bytes = null; partial.categories[0].partial = true;
assert.equal(parse(partial).categories[0].bytes, null);
console.log('PASS: storage schema, unknown values, duplicate categories and independent physical totals');
