// Fake storage reader/service used only by the isolated controller tests.
const [operation, mode = 'ok'] = process.argv.slice(2);
if (mode === 'hang') {
  setTimeout(() => process.exit(0), 10000);
} else if (mode === 'fail') {
  process.exitCode = 1;
} else if (operation === 'scan') {
  setTimeout(() => process.exit(0), mode === 'slow' ? 250 : 30);
} else if (mode === 'invalid') {
  console.log('{bad report');
} else {
  console.log(JSON.stringify({
    schemaVersion: mode === 'legacy' ? 1 : 2,
    measuredAt: Date.now() - (mode === 'stale' ? 86400000 : 0),
    estimated: true,
    disk: {totalBytes: 1000, usedBytes: 600, availableBytes: 380},
    categories: ['docker', 'nix', 'applications', 'personal', 'vm', 'other'].map(id => ({
      id, bytes: id === 'vm' ? 0 : 120, partial: false,
      ...(id === 'applications' ? {cacheBytes: 50, dataBytes: 70} : {}),
      ...(id === 'docker' ? {breakdown: ['layers', 'volumes', 'buildCache', 'containers', 'other']
        .map(id => ({id, bytes: 24, partial: false}))} : {}),
      ...(id === 'personal' ? {largestEntries: [{path: '~/Projects', bytes: 100, kind: 'directory', partial: false}]} : {})
    }))
  }));
}
