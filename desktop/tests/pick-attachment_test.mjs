import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, readdir, rm} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const temporary = await mkdtemp(path.join(os.tmpdir(), 'beeper-picker-test-'));
try {
  const bin = path.join(temporary, 'bin'), scratch = path.join(temporary, 'scratch');
  await mkdir(bin); await mkdir(scratch);
  // Replace only the terminal: exercise the production shell and JSON encoding.
  await writeFile(path.join(bin, 'ghostty'), `#!/usr/bin/env bash
set -eu
[[ "$1" == --gtk-single-instance=false ]]
[[ "$2" == '--title=Attach a file' ]]
[[ "$3" == -e && "$4" == yazi && "$5" == --chooser-file=* ]]
[[ "$6" == "$HOME" ]]
case "$PICKER_TEST_MODE" in
  cancel) exit 0 ;;
  fail) exit 1 ;;
  *) printf '%s' "$PICKER_TEST_SELECTION" > "\${5#--chooser-file=}" ;;
esac
`, {mode: 0o700});
  const script = fileURLToPath(new URL('../../tools/quickshell/pick-attachment.sh', import.meta.url));
  function run(mode, selection = '') {
    return spawnSync('bash', [script], {encoding: 'utf8', env: {...process.env,
      PATH: bin + path.delimiter + process.env.PATH, TMPDIR: scratch,
      PICKER_TEST_MODE: mode, PICKER_TEST_SELECTION: selection}});
  }
  for (const file of ['/tmp/photo.jpg', '/tmp/été "photo" $literal `name`.png', '/tmp/ trailing space ']) {
    for (const ending of ['', '\n']) {
      const result = run('select', file + ending);
      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(JSON.parse(result.stdout), {path: file});
    }
  }
  assert.deepEqual(JSON.parse(run('cancel').stdout), {path: ''});
  const multiple = run('select', '/tmp/one\n/tmp/two\n');
  assert.notEqual(multiple.status, 0);
  assert.match(multiple.stderr, /Choose one file/);
  const failure = run('fail');
  assert.notEqual(failure.status, 0);
  assert.match(failure.stderr, /Could not open Yazi/);
  assert.deepEqual(await readdir(scratch), [], 'All temporary selections are removed');
  console.log('PASS: attachment chooser selection, cancellation, failures, quoting and cleanup');
} finally {
  await rm(temporary, {recursive: true, force: true});
}
