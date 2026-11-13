import assert from 'node:assert/strict';
import {test} from 'node:test';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {mkdtemp, writeFile, readFile, rm} from 'node:fs/promises';
import {spectrum, SpectrumStream, windowSize, hopSize, sampleRate, bandCount, bandEdges} from './spectrum.mjs';

const tone = (hz, amplitude = 0.01) => Float32Array.from({length: windowSize}, (_, i) => amplitude * Math.sin(2 * Math.PI * hz * i / sampleRate));
const dominant = levels => levels.indexOf(Math.max(...levels));
test('low and high tones light the matching frequency bands', () => {
  for (const hz of [250, 1000, 4000]) {
    const band = dominant(spectrum(tone(hz)));
    assert.ok(hz >= bandEdges[band] && hz < bandEdges[band + 1]);
  }
});
test('silence, DC and invalid samples stay dark', () => {
  for (const value of [0, 0.3, NaN, Infinity])
    assert.deepEqual(spectrum(new Float32Array(windowSize).fill(value)), Array(bandCount).fill(0));
});
test('absolute scale is unchanged by loud history and responds to quieter sounds', () => {
  const quiet = spectrum(tone(1000));
  const loud = spectrum(tone(1000, 0.5));
  assert.deepEqual(spectrum(tone(1000)), quiet);
  assert.ok(loud[dominant(quiet)] > quiet[dominant(quiet)]);
  assert.ok(quiet[dominant(quiet)] > 0.1 && quiet[dominant(quiet)] < 0.9);
  assert.ok(loud.every(value => value >= 0 && value <= 1));
});
test('fragmented PCM produces the same overlapping frames as contiguous input', () => {
  const samples = Float32Array.from({length: windowSize + hopSize * 4}, (_, i) => 0.02 * Math.sin(2 * Math.PI * 500 * i / sampleRate));
  const pcm = Buffer.from(samples.buffer), expected = [], actual = [];
  new SpectrumStream().push(pcm, levels => expected.push(levels));
  const stream = new SpectrumStream();
  for (let offset = 0; offset < pcm.length; offset += 73) stream.push(pcm.subarray(offset, offset + 73), levels => actual.push(levels));
  assert.equal(actual.length, 5); assert.deepEqual(actual, expected);
  assert.ok(stream.pending.length < windowSize * 4);
});
test('capture process releases its recorder on termination without opening a microphone', {timeout: 5000}, async () => {
  const dir = await mkdtemp('/tmp/voice-spectrum-test-');
  let capture, pid;
  try {
    const recorder = dir + '/recorder';
    await writeFile(recorder, '#!' + process.execPath + '\n'
      + 'require("node:fs").writeFileSync(process.env.SPECTRUM_TEST_PID,String(process.pid));'
      + 'setInterval(()=>process.stdout.write(Buffer.alloc(2048)),32);', {mode: 0o700});
    capture = spawn(process.execPath, [new URL('./capture.mjs', import.meta.url).pathname, recorder],
      {env: {...process.env, SPECTRUM_TEST_PID: dir + '/pid'}, stdio: ['ignore', 'pipe', 'pipe']});
    await once(capture.stdout, 'data');
    pid = Number(await readFile(dir + '/pid', 'utf8'));
    const exit = once(capture, 'exit'); capture.kill('SIGTERM');
    await exit;
    assert.throws(() => process.kill(pid, 0), {code: 'ESRCH'});
  } finally {
    capture?.kill('SIGKILL');
    if (pid) { try { process.kill(pid, 'SIGKILL'); } catch {} }
    await rm(dir, {recursive: true, force: true});
  }
});
