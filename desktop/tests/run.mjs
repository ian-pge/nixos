// Local regression entry point; never launches desktop/shell.qml or activates Nix.
// node desktop/tests/run.mjs /path/to/quickshell [--wayland]
// Optional: QMLTESTRUNNER=/path/to/qmltestrunner BEEPER_TEST_BACKEND=/path/to/backend
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, mkdir, writeFile, rm} from 'node:fs/promises';
import {existsSync, realpathSync} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const qs = process.argv.slice(2).find(arg => !arg.startsWith('--')) || 'qs';
const temporary = await mkdtemp(path.join(os.tmpdir(), 'desktop-tests-'));
const busConfig = path.join(temporary, 'dbus.conf');
await writeFile(busConfig, `<busconfig><type>session</type><listen>unix:tmpdir=${temporary}</listen>
  <policy context="default"><allow send_destination="*" eavesdrop="true"/>
  <allow eavesdrop="true"/><allow own="*"/></policy></busconfig>`);
const baseEnv = {...process.env, QT_QPA_PLATFORM: 'offscreen', QT_QUICK_BACKEND: 'software',
  QT_NO_XDG_DESKTOP_PORTAL: '1', QUICKSHELL_NOTIFICATION_TEST: '1',
  PATH: path.join(here, 'fixtures') + path.delimiter + process.env.PATH,
  XDG_CACHE_HOME: path.join(temporary, 'cache'), XDG_STATE_HOME: path.join(temporary, 'state')};
delete baseEnv.WAYLAND_DISPLAY;
delete baseEnv.HYPRLAND_INSTANCE_SIGNATURE;
await mkdir(baseEnv.XDG_CACHE_HOME); await mkdir(baseEnv.XDG_STATE_HOME);
let passed = 0;
async function run(command, args, env = baseEnv, expected = null) {
  const label = args.find(arg => /(?:_test\.mjs|tst_.*\.qml|messenger-load_test\.qml)$/.test(arg)) || args.join(' ');
  console.log('\nRUN ' + path.basename(label));
  const child = spawn(command, args, {env, stdio: ['ignore', 'pipe', 'pipe'], detached: true});
  let output = '';
  for (const stream of [child.stdout, child.stderr]) stream.on('data', data => { output += data; process.stdout.write(data); });
  const timer = setTimeout(() => { try { process.kill(-child.pid, 'SIGKILL'); } catch {} }, 90_000);
  try {
    const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('exit', resolve); });
    assert.equal(code, 0, 'Failed: ' + label);
    if (expected) assert.match(output, expected, 'No successful test result: ' + label);
    assert.doesNotMatch(output, /TypeError:|ReferenceError:|Binding loop detected|Cannot assign to non-existent property/);
    ++passed;
  } finally { clearTimeout(timer); }
}
async function qml(file, env = baseEnv) {
  await run('dbus-run-session', ['--config-file=' + busConfig, '--', qs, '-p', path.join(here, file), '--no-color'],
    env, /\d+ passed, 0 failed/);
}
try {
  for (const file of ['audio-routes_test.mjs', 'calendar-navigation_test.mjs', 'capsule-content_test.mjs', 'launcher-logic_test.mjs', 'system-panel-state_test.mjs', 'workspaces_test.mjs', 'messenger-host_test.mjs']) {
    if (existsSync(path.join(here, file))) await run(process.execPath, [path.join(here, file)]);
  }
  for (const file of ['tst_AcceleratedScroll.qml', 'tst_KeyedListModel.qml', 'tst_BeeperData.qml', 'tst_BeeperConnections.qml', 'tst_BeeperComposer.qml', 'tst_BeeperPanel.qml', 'tst_BeeperKeyboard.qml', 'tst_BeeperArchives.qml', 'tst_BeeperUnreadOrder.qml', 'tst_BeeperSearch.qml', 'tst_BeeperPagination.qml', 'tst_BeeperQuotes.qml', 'tst_BeeperMedia.qml', 'tst_BeeperPeople.qml', 'tst_BeeperVideo.qml', 'tst_BeeperBubble.qml',
    'tst_MessengerController.qml', 'tst_LauncherControllers.qml', 'tst_NetworkControllers.qml',
    'tst_UpdateControllers.qml', 'tst_FeatureControllers.qml', 'tst_CollectorLifecycle.qml',
    'tst_ShellCoordinator.qml', 'tst_SystemData.qml',
    'tst_WeatherData.qml', 'tst_NotificationData.qml', 'tst_NotificationPopup.qml', 'tst_WorkspaceSwitcher.qml',
    '../pill-test.qml', '../selection-test.qml'])
    await qml(file);
  if (process.env.BEEPER_TEST_BACKEND) await qml('tst_MessengerProtocol.qml');
  else console.log('SKIP Go protocol integration: set BEEPER_TEST_BACKEND to the built demo-capable executable.');

  const testRunner = process.env.QMLTESTRUNNER || process.env.PATH.split(path.delimiter)
    .map(directory => path.join(directory, 'qmltestrunner')).find(existsSync);
  if (testRunner) {
    // Nix's unwrapped Qt test tool needs the adjacent Qt QML import directory.
    const imports = path.join(path.dirname(path.dirname(realpathSync(testRunner))), 'lib/qt-6/qml');
    const env = {...baseEnv, QML_IMPORT_PATH: [imports, process.env.QML_IMPORT_PATH].filter(Boolean).join(path.delimiter)};
    for (const file of ['tst_CalendarPanel.qml', 'tst_KeyboardSheet.qml', 'tst_SystemPanel.qml', 'tst_NotificationInputGuard.qml'])
      await run('dbus-run-session', ['--config-file=' + busConfig, '--', testRunner, '-input', path.join(here, file)], env,
        /Totals: \d+ passed, 0 failed/);
  } else console.log('SKIP plain Qt views: set QMLTESTRUNNER (available in the cpp development shell).');

  if (process.env.WAYLAND_DISPLAY) {
    // Compile only; this harness never creates the desktop services.
    const env = {...baseEnv, WAYLAND_DISPLAY: process.env.WAYLAND_DISPLAY, QT_QPA_PLATFORM: 'wayland'};
    await run('dbus-run-session', ['--config-file=' + busConfig, '--', qs, '-p', path.join(here, 'messenger-load_test.qml'), '--no-color'],
      env, /Messenger integration: all components compile/);
  } else console.log('SKIP Wayland graph compile: no Wayland display.');
  if (process.argv.includes('--wayland')) {
    for (const mode of ['--avatar', '--bubble', '--media', '--people', '--host', '--desktop'])
      await run(process.execPath, [path.join(here, 'messenger-wayland_test.mjs'), qs, mode], process.env);
  }
  console.log(`\nPASS: ${passed} desktop regression suites. Optional skips are listed above.`);
} finally {
  await rm(temporary, {recursive: true, force: true});
}
