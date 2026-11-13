import {spawn} from 'node:child_process';
import {SpectrumStream} from './spectrum.mjs';

// Started only while dictating. PipeWire uses the default input, just like this
// configuration's VoxType audio.device = "default". No audio is written to disk.
const offline = process.argv[2] === '--stdin';
const recorder = offline ? null : spawn(process.argv[2] || 'pw-record', [
  '--raw', '--format', 'f32', '--rate', '16000', '--channels', '1', '--latency', '32ms',
  '--properties', '{ application.name = "Dictation spectrum" node.restore-props = false }', '-'
], {stdio: ['ignore', 'pipe', 'inherit']});
const input = recorder?.stdout || process.stdin;
const stream = new SpectrumStream();
let stopping = false;
function stop(code = 0) {
  if (stopping) return;
  stopping = true;
  input.destroy();
  if (recorder && recorder.exitCode === null) {
    recorder.kill('SIGTERM');
    setTimeout(() => { recorder.kill('SIGKILL'); process.exit(code); }, 500).unref();
  } else process.exit(code);
}
process.on('SIGTERM', () => stop());
process.on('SIGINT', () => stop());
process.stdout.on('error', error => stop(error.code === 'EPIPE' ? 0 : 1));
input.on('data', chunk => stream.push(chunk, bands => {
  // A stalled view must not accumulate an ever-growing audio history.
  if (!stopping && !process.stdout.writableNeedDrain)
    process.stdout.write(JSON.stringify({bands}) + '\n');
}));
input.on('error', error => { console.error(error.message); stop(1); });
recorder?.on('error', error => { console.error(error.message); stop(1); });
recorder?.on('exit', code => { process.exitCode = stopping ? 0 : (code || 1); });
