// Compile the real messenger/bar graph in an isolated Wayland session.
// Usage: node messenger-wayland_test.mjs /path/to/packaged/quickshell
import assert from "node:assert/strict";
import {spawn, spawnSync, execFile} from "node:child_process";
import {mkdtemp, readdir, rm, writeFile} from "node:fs/promises";
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
const runtime = process.env.XDG_RUNTIME_DIR;
const env = {
  ...process.env,
  XDG_RUNTIME_DIR: runtime,
  WAYLAND_DISPLAY: path.resolve(process.env.XDG_RUNTIME_DIR, process.env.WAYLAND_DISPLAY),
  QT_QPA_PLATFORM: "wayland",
  QSG_RENDER_LOOP: "threaded",
  HYPRLAND_NO_SD_VARS: "1", HYPRLAND_NO_SD_NOTIFY: "1", HYPRLAND_NO_SD_TARGET: "1",
  HYPRLAND_NO_RT: "1", AQ_DRM_DEVICES: "/dev/null", AQ_NO_MODIFIERS: "1"
};
delete env.HYPRLAND_INSTANCE_SIGNATURE;
delete env.NOTIFY_SOCKET;
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
  compositor = spawn("Hyprland", ["--config", path.resolve(here, "../../../../tools/liquid-glass/tests/hyprland.lua")], {env, detached: true});
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
  shell = spawn(quickshell, ["--path", path.join(here, "messenger-load_test.qml"), "--no-color"], {env, detached: true});
  collect(shell, data => { shellLog += data; });
  await until(() => {
    if (compositor.exitCode !== null) throw new Error("Nested compositor exited during QML compilation");
    if (/Messenger integration:/.test(shellLog)) return true;
    if (shell.exitCode !== null) throw new Error("Quickshell exited before reporting the compile result");
    return false;
  }, "messenger QML compilation");
  assert.match(shellLog, /Messenger integration: all components compile/, shellLog);
  console.log("PASS: BeeperData, BeeperPanel, NotificationData, StatusData and Bar compile with the Wayland backend in a private session");
} catch (error) {
  console.error(compositorLog);
  console.error(shellLog);
  throw error;
} finally {
  await stop(shell);
  await stop(compositor);
}
