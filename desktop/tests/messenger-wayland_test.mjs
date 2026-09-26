// Compile the real messenger/bar graph in an isolated Wayland session.
// Usage: node messenger-wayland_test.mjs /path/to/packaged/quickshell [--avatar|--bubble|--media|--people|--host|--desktop|--preview]
import assert from "node:assert/strict";
import {spawn, spawnSync, execFile} from "node:child_process";
import {mkdtemp, mkdir, readdir, readFile, rm, writeFile} from "node:fs/promises";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {promisify} from "node:util";

const filename = fileURLToPath(import.meta.url);
const here = path.dirname(filename);
assert.ok(process.env.XDG_RUNTIME_DIR && process.env.WAYLAND_DISPLAY, "A Wayland desktop is required for the nested compositor");
if (process.env.QS_MESSENGER_PRIVATE_DBUS !== "1") {
  const runtime = await mkdtemp("/tmp/qb-");
  let status = 1;
  try {
    // No service directories: Qt must not autostart the user's desktop portals
    // or their document mounts merely while compiling the component graph.
    const busConfig = path.join(runtime, "dbus.conf");
    await writeFile(busConfig, `<busconfig><type>session</type><listen>unix:tmpdir=${runtime}</listen>
      <policy context="default"><allow send_destination="*" eavesdrop="true"/>
      <allow eavesdrop="true"/><allow own="*"/></policy></busconfig>`);
    const child = spawnSync("dbus-run-session", ["--config-file=" + busConfig, "--", process.execPath, filename, ...process.argv.slice(2)], {
      stdio: "inherit",
      env: {...process.env, QS_MESSENGER_PRIVATE_DBUS: "1", XDG_RUNTIME_DIR: runtime,
        WAYLAND_DISPLAY: path.resolve(process.env.XDG_RUNTIME_DIR, process.env.WAYLAND_DISPLAY)}
    });
    if (child.error) throw child.error;
    status = child.status ?? 1;
  } finally {
    await rm(runtime, {recursive: true, force: true, maxRetries: 10, retryDelay: 100});
  }
  process.exit(status);
}

const quickshell = process.argv[2] || "qs";
const renderAvatar = process.argv.includes("--avatar");
const renderBubble = process.argv.includes("--bubble");
const renderMedia = process.argv.includes("--media");
const renderPeople = process.argv.includes("--people");
const testHost = process.argv.includes("--host");
const testDesktop = process.argv.includes("--desktop");
const renderPreview = process.argv.includes("--preview");
if (testHost) {
  // The mask belongs to Bar, not Host. Protect that caller's public contract
  // without starting the desktop services just to instantiate Bar.
  const barSource = await readFile(path.join(here, "../bar/Bar.qml"), "utf8");
  assert.doesNotMatch(barSource, /\bbeeperBubble\./, "Bar must not access the host's private bubble id");
  assert.match(barSource, /Region\s*\{\s*item:\s*messengerSurface\.presented\s*\?\s*messengerSurface\.surfaceItem\s*:\s*null\s*\}/,
    "The messenger input mask must track the presented host surface through closing animations");
}
const runtime = process.env.XDG_RUNTIME_DIR;
const env = {
  ...process.env,
  XDG_RUNTIME_DIR: runtime,
  XDG_CACHE_HOME: path.join(runtime, "cache"),
  XDG_STATE_HOME: path.join(runtime, "state"),
  WAYLAND_DISPLAY: path.resolve(process.env.XDG_RUNTIME_DIR, process.env.WAYLAND_DISPLAY),
  QT_QPA_PLATFORM: "wayland",
  QSG_RENDER_LOOP: "threaded",
  HYPRLAND_NO_SD_VARS: "1", HYPRLAND_NO_SD_NOTIFY: "1", HYPRLAND_NO_SD_TARGET: "1",
  HYPRLAND_NO_RT: "1", AQ_DRM_DEVICES: "/dev/null", AQ_NO_MODIFIERS: "1"
};
delete env.HYPRLAND_INSTANCE_SIGNATURE;
delete env.NOTIFY_SOCKET;
delete env.QT_QUICK_BACKEND;
const exec = promisify(execFile);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let compositor, shell;
let compositorLog = "", shellLog = "";
let spawnError;

async function until(predicate, description) {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    if (spawnError) throw spawnError;
    if (await predicate()) return;
    await delay(50);
  }
  throw new Error("Timeout: " + description);
}
function collect(child, append) {
  child.on("error", error => { spawnError = error; });
  for (const stream of [child.stdout, child.stderr]) stream.on("data", data => append(data.toString()));
}
async function stop(child) {
  if (!child?.pid) return;
  try { process.kill(-child.pid, "SIGTERM"); } catch {}
  await delay(200);
  try { process.kill(-child.pid, "SIGKILL"); } catch {}
  child.stdout?.destroy();
  child.stderr?.destroy();
}

try {
  await mkdir(env.XDG_CACHE_HOME, {recursive: true});
  await mkdir(env.XDG_STATE_HOME, {recursive: true});
  let compositorConfig = path.resolve(here, "../../tools/liquid-glass/tests/hyprland.lua");
  if (testHost) {
    const baseConfig = await readFile(compositorConfig, "utf8");
    compositorConfig = path.join(runtime, "hyprland-photo.lua");
    await writeFile(compositorConfig, baseConfig + '\nhl.config({ decoration = { blur = { enabled = true } } })\n'
      + 'hl.layer_rule({ match = { namespace = "quickshell-messenger-photo" }, blur = true, ignore_alpha = 0 })\n');
  }
  compositor = spawn("Hyprland", ["--config", compositorConfig], {env, detached: true});
  collect(compositor, data => { compositorLog += data; });
  await until(async () => {
    if (compositor.exitCode !== null) throw new Error("Nested compositor exited with " + compositor.exitCode);
    const names = await readdir(path.join(runtime, "hypr")).catch(() => []);
    const display = (await readdir(runtime)).find(name => /^wayland-\d+$/.test(name));
    if (!names.length || !display) return false;
    env.HYPRLAND_INSTANCE_SIGNATURE = names[0];
    env.WAYLAND_DISPLAY = display;
    try {
      const monitors = JSON.parse((await exec("hyprctl", ["-j", "monitors"], {env, timeout: 2000})).stdout);
      return monitors.some(monitor => monitor.width > 0 && monitor.height > 0);
    } catch { return false; }
  }, "nested compositor readiness");
  assert.equal((await exec("hyprctl", ["configerrors"], {env, timeout: 2000})).stdout.trim(), "", "Nested compositor configuration must be valid");
  const testFile = renderAvatar ? "./tst_BeeperAvatar.qml" : renderBubble ? "./tst_BeeperBubble.qml" : renderMedia ? "./tst_BeeperMedia.qml"
    : renderPeople ? "./tst_BeeperPeople.qml"
    : testHost ? "./tst_MessengerHost.qml" : testDesktop ? "./tst_DesktopComposition.qml"
    : renderPreview ? "../preview.qml" : "./messenger-load_test.qml";
  shell = spawn(quickshell, ["--path", path.join(here, testFile), "--no-color"], {env, detached: true});
  collect(shell, data => { shellLog += data; });
  await until(() => {
    if (compositor.exitCode !== null) throw new Error("Nested compositor exited during QML compilation");
    if (renderPreview && shell.exitCode === 0) return true;
    if ((renderAvatar ? /BeeperAvatar:/ : renderBubble ? /BeeperBubble:/ : renderMedia ? /BeeperMedia:/ : renderPeople ? /BeeperPeople:/ : testHost ? /MessengerHost:/ : testDesktop ? /DesktopComposition:/ : /Messenger integration:/).test(shellLog)) return true;
    if (shell.exitCode !== null) throw new Error("Quickshell exited before reporting the compile result");
    return false;
  }, "messenger QML compilation");
  if (renderPreview) {
    const report = JSON.parse(shellLog.match(/Messenger preview: (\{[^\n]+\})/)?.[1] || "{}");
    assert.equal(report.expanded, true, shellLog);
    assert.equal(report.progress, Number(env.BEEPER_PREVIEW_PROGRESS || 1), shellLog);
  } else assert.match(shellLog, renderAvatar ? /BeeperAvatar: \d+ passed, 0 failed/
    : renderBubble ? /BeeperBubble: \d+ passed, 0 failed/ : renderMedia ? /BeeperMedia: \d+ passed, 0 failed/ : renderPeople ? /BeeperPeople: \d+ passed, 0 failed/ : testHost ? /MessengerHost: \d+ passed, 0 failed/
    : testDesktop ? /DesktopComposition: \d+ passed, 0 failed/
    : /Messenger integration: all components compile/, shellLog);
  assert.doesNotMatch(shellLog, /(?:ERROR|TypeError|ReferenceError|Binding loop|Cannot assign|Unable to assign \[undefined\])/, shellLog);
  console.log(renderAvatar
    ? "PASS: avatar photo is circular, network badge remains visible, contact fallback updates correctly"
    : renderBubble ? "PASS: independent bubble geometry, reversible animation and concurrent chat/audio focus"
    : renderMedia ? "PASS: message/media layout and native search highlight pixels"
    : renderPeople ? "PASS: per-person reaction pills, reader avatars, wrapping and live profile updates"
    : testHost ? "PASS: MessengerHost layer surface, keyboard ownership, native dialogs and focus restoration"
    : testDesktop ? "PASS: complete desktop composition and real Bar instantiate with disabled services"
    : renderPreview ? "PASS: messenger preview rendered with the normal Wayland scene graph"
    : "PASS: messenger, feature controllers, shell coordinator and Bar compile in a private Wayland session");
} catch (error) {
  console.error(compositorLog);
  console.error(shellLog);
  throw error;
} finally {
  await stop(shell);
  await stop(compositor);
}
