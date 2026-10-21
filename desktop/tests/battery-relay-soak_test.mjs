// Opt-in, read-only observation of the REAL bar. No second BLE subscriber,
// scan, device disconnection, APK installation or shell restart.
// node desktop/tests/battery-relay-soak_test.mjs --seconds 420 [--require-fitbit] [--require-no-discovery]
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {setTimeout} from 'node:timers/promises';

const args = process.argv.slice(2);
assert.equal(args[0], '--seconds', 'Explicit opt-in required: --seconds 420 [--require-fitbit]');
const seconds = Number(args[1]);
assert(Number.isInteger(seconds) && seconds >= 180 && seconds <= 3600);
assert(args.slice(2).every(arg => ['--require-fitbit', '--require-no-discovery'].includes(arg)));
const requireFitbit = args.includes('--require-fitbit');
const requireNoDiscovery = args.includes('--require-no-discovery');
const run = promisify(execFile);
const qs = process.env.QS_TEST_BINARY || 'qs';
const started = Date.now();
let stableSince = 0, priorPhoneReportAge = null, priorEarbudReportAge = null;
let phoneReports = 0, earbudReports = 0, lastLog = 0;
let maxPhoneReportAge = 0, maxEarbudReportAge = 0;

while (Date.now() - started < (seconds + 60) * 1000) {
  const {stdout} = await run(qs, ['ipc', '-c', 'top-bar', 'call', 'topbar', 'batteryStatus'], {timeout: 5000});
  const status = JSON.parse(stdout);
  const discovering = requireNoDiscovery ? (await run('busctl', ['--system', 'get-property', 'org.bluez',
    '/org/bluez/hci0', 'org.bluez.Adapter1', 'Discovering'], {timeout: 3000})).stdout.trim() !== 'b false' : false;
  const available = status.connected && status.phone.length === 1
    && status.earbudDataConnected && status.earbuds.length === 1
    && status.earbuds[0].percent !== null
    && (!requireFitbit || status.fitbit.length === 1);
  if (!stableSince) {
    if (!available || discovering) { await setTimeout(1000); continue; }
    stableSince = Date.now();
  }
  assert(available, 'A required battery disappeared during the observation: ' + JSON.stringify(status));
  assert(Number.isFinite(status.phoneReportAgeMs) && status.phoneReportAgeMs >= -5000 && status.phoneReportAgeMs < 180000);
  assert.equal(status.phoneMode, 'passive');
  assert.equal(status.earbudMode, 'passive');
  assert(!discovering, 'Active Bluetooth discovery started during the passive observation');
  assert(Number.isFinite(status.earbudReportAgeMs) && status.earbudReportAgeMs >= -5000 && status.earbudReportAgeMs < 180000);
  assert(Number.isFinite(status.earbudAgeMs) && status.earbudAgeMs >= -5000);
  assert(status.earbudReceiverRunning && status.receiverRunning);
  if (priorPhoneReportAge !== null && status.phoneReportAgeMs < priorPhoneReportAge - 2000) phoneReports++;
  if (priorEarbudReportAge !== null && status.earbudReportAgeMs < priorEarbudReportAge - 2000) earbudReports++;
  priorPhoneReportAge = status.phoneReportAgeMs; priorEarbudReportAge = status.earbudReportAgeMs;
  maxPhoneReportAge = Math.max(maxPhoneReportAge, status.phoneReportAgeMs);
  maxEarbudReportAge = Math.max(maxEarbudReportAge, status.earbudReportAgeMs);
  const elapsed = Date.now() - stableSince;
  if (Date.now() - lastLog >= 30000 || elapsed >= seconds * 1000) {
    console.log(JSON.stringify({elapsedSeconds: Math.floor(elapsed / 1000),
      phoneReportAgeMs: status.phoneReportAgeMs, earbudAgeMs: status.earbudAgeMs,
      earbudReportAgeMs: status.earbudReportAgeMs,
      phoneReports, earbudReports, fitbitAvailable: status.fitbit.length === 1}));
    lastLog = Date.now();
  }
  if (elapsed >= seconds * 1000) {
    assert(phoneReports >= Math.floor(seconds / 100), 'Expected repeated phone monitor status reports');
    assert(earbudReports >= Math.floor(seconds / 60), 'Expected repeated passive monitor status reports');
    console.log('PASS: uninterrupted passive battery monitoring; ' + JSON.stringify({seconds, phoneReports, earbudReports, maxPhoneReportAge, maxEarbudReportAge, requireNoDiscovery}));
    process.exit(0);
  }
  await setTimeout(1000);
}
throw new Error('The actual bar did not provide the required stable interval');
