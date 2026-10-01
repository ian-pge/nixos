// Exercise the real Lua policy and window moves on private virtual outputs.
// Never disables or dispatches to a monitor in the user's compositor.
import assert from "node:assert/strict";
import {spawn, spawnSync, execFile} from "node:child_process";
import {mkdtemp, mkdir, readFile, readdir, rm, writeFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
import path from "node:path";
import {promisify} from "node:util";

const filename = fileURLToPath(import.meta.url);
const here = path.dirname(filename);
assert.ok(process.env.WAYLAND_DISPLAY && process.env.XDG_RUNTIME_DIR);
if (process.env.QS_WORKSPACE_PRIVATE_BUS !== "1") {
  const runtime = await mkdtemp("/tmp/qw-");
  let status = 1;
  try {
    const bus = path.join(runtime, "dbus.conf");
    await writeFile(bus, `<busconfig><type>session</type><listen>unix:tmpdir=${runtime}</listen>
      <policy context="default"><allow send_destination="*" eavesdrop="true"/>
      <allow eavesdrop="true"/><allow own="*"/></policy></busconfig>`);
    const child = spawnSync("dbus-run-session", ["--config-file=" + bus, "--", process.execPath, filename], {
      stdio: "inherit", env: {...process.env, QS_WORKSPACE_PRIVATE_BUS: "1", XDG_RUNTIME_DIR: runtime,
        WAYLAND_DISPLAY: path.resolve(process.env.XDG_RUNTIME_DIR, process.env.WAYLAND_DISPLAY)}
    });
    if (child.error) throw child.error;
    status = child.status ?? 1;
  } finally { await rm(runtime, {recursive: true, force: true, maxRetries: 10, retryDelay: 100}); }
  process.exit(status);
}

const runtime = process.env.XDG_RUNTIME_DIR;
const env = {...process.env, QT_QPA_PLATFORM: "wayland", QT_NO_XDG_DESKTOP_PORTAL: "1",
  XDG_CACHE_HOME: path.join(runtime, "cache"), XDG_STATE_HOME: path.join(runtime, "state"),
  HYPRLAND_NO_SD_VARS: "1", HYPRLAND_NO_SD_NOTIFY: "1", HYPRLAND_NO_SD_TARGET: "1",
  HYPRLAND_NO_RT: "1", AQ_DRM_DEVICES: "/dev/null", AQ_NO_MODIFIERS: "1"};
delete env.HYPRLAND_INSTANCE_SIGNATURE; delete env.NOTIFY_SOCKET; delete env.QT_QUICK_BACKEND;
const exec = promisify(execFile);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let compositor, shell, failure;
let log = "";
function launch(command, args) {
  const child = spawn(command, args, {env, detached: true, stdio: ["ignore", "pipe", "pipe"]});
  child.on("error", error => { failure = error; });
  for (const stream of [child.stdout, child.stderr]) stream.on("data", data => { log += data; });
  return child;
}
async function ctl(...args) {
  assert.ok(env.HYPRLAND_INSTANCE_SIGNATURE, "Only the private compositor may receive commands");
  return (await exec("hyprctl", args, {env, timeout: 5000})).stdout.trim();
}
async function json(command) { return JSON.parse(await ctl("-j", command)); }
async function until(predicate, label) {
  const end = Date.now() + 20000;
  while (Date.now() < end) {
    if (failure) throw failure;
    if (compositor?.exitCode !== null) throw new Error("Private compositor exited");
    if (await predicate()) return;
    await delay(80);
  }
  throw new Error("Timeout: " + label);
}
async function stop(child) {
  if (!child?.pid) return;
  try { process.kill(-child.pid, "SIGTERM"); } catch {}
  await delay(200);
  try { process.kill(-child.pid, "SIGKILL"); } catch {}
  child.stdout?.destroy(); child.stderr?.destroy();
}
try {
  await mkdir(env.XDG_CACHE_HOME); await mkdir(env.XDG_STATE_HOME);
  const policy = await readFile(path.join(here, "../workspace-policy.lua"), "utf8");
  const config = path.join(runtime, "hyprland.lua");
  await writeFile(config, `hl.config({animations={enabled=false}, decoration={blur={enabled=false}, shadow={enabled=false}},
    misc={disable_hyprland_logo=true,disable_splash_rendering=true}, cursor={no_hardware_cursors=true},
    ecosystem={no_update_news=true}})
    hl.monitor({output="",mode="1280x800@60",position="auto",scale=1})\n` + policy);
  compositor = launch("Hyprland", ["--config", config]);
  await until(async () => {
    const names = await readdir(path.join(runtime, "hypr")).catch(() => []);
    const display = (await readdir(runtime)).find(name => /^wayland-\d+$/.test(name));
    if (!names.length || !display) return false;
    env.HYPRLAND_INSTANCE_SIGNATURE = names[0]; env.WAYLAND_DISPLAY = display;
    try { return (await json("monitors")).length > 0; } catch { return false; }
  }, "private compositor readiness");
  const originalOutputs = (await json("monitors")).map(monitor => monitor.name);
  assert.equal(await ctl("output", "create", "headless", "eDP-TEST"), "ok");
  assert.equal(await ctl("output", "create", "headless", "DP-2"), "ok");
  await until(async () => (await json("monitors")).some(monitor => monitor.name === "eDP-TEST"), "internal output");
  for (const name of originalOutputs)
    assert.equal(await ctl("eval", `hl.monitor({output=${JSON.stringify(name)},disabled=true})`), "ok");
  await until(async () => {
    const spaces = await json("workspaces");
    return Array.from({length: 10}, (_, index) => index + 1).every(id =>
      spaces.some(workspace => workspace.id === id && workspace.monitor === (id <= 5 ? "DP-2" : "eDP-TEST")));
  }, "five workspaces on each private output");
  assert.equal(await ctl("configerrors"), "");

  shell = launch("qs", ["-p", path.join(here, "workspace-hotplug.qml"), "--no-color"]);
  await until(async () => (await json("clients")).filter(client => client.title.startsWith("Workspace test ")).length === 2,
    "two test windows");
  const clients = await json("clients");
  const first = clients.find(client => client.title === "Workspace test A");
  const second = clients.find(client => client.title === "Workspace test B");
  for (const [client, id] of [[first, 2], [second, 7]]) {
    assert.equal(await ctl("eval", `hl.dispatch(hl.dsp.window.move({window="address:${client.address}",workspace=${id},follow=false}))`), "ok");
  }
  await until(async () => {
    const windows = await json("clients");
    return windows.some(w => w.address === first.address && w.workspace.id === 2)
      && windows.some(w => w.address === second.address && w.workspace.id === 7);
  }, "test window placement");
  assert.equal(await ctl("output", "remove", "DP-2"), "ok");
  await until(async () => {
    const windows = await json("clients");
    return [first, second].every(saved => windows.some(w => w.address === saved.address && w.workspace.id === 2));
  }, "7-to-2 merge without closing either window");
  await until(async () => (await json("workspaces")).filter(w => w.id > 0).every(w => w.id <= 5), "five solo workspaces");
  assert.equal(await ctl("eval", 'assert(quickshell_workspace_target(6) == nil); assert(quickshell_workspace_target(1) == 1)'), "ok");

  assert.equal(await ctl("output", "create", "headless", "DP-2"), "ok");
  await until(async () => {
    const spaces = await json("workspaces");
    const outputs = await json("monitors");
    return spaces.some(w => w.id === 2 && w.monitor === "DP-2")
      && outputs.some(m => m.name === "eDP-TEST" && m.activeWorkspace.id >= 6 && m.activeWorkspace.id <= 10);
  }, "reconnection restores the per-screen ranges");
  assert.equal((await json("clients")).length, 2);
  assert.equal(await ctl("output", "remove", "eDP-TEST"), "ok");
  await until(async () => (await json("workspaces")).filter(w => w.id > 0).every(w => w.id <= 5), "external-only layout");
  assert.equal(await ctl("configerrors"), "");
  assert.doesNotMatch(log, /ERROR|error in timer callback|stack traceback/);
  console.log("PASS: native Hyprland hotplug, window-preserving merge, reconnect, solo output and cleanup");
} catch (error) {
  console.error(log);
  if (env.HYPRLAND_INSTANCE_SIGNATURE) {
    console.error(await ctl("configerrors").catch(() => ""));
    console.error(await ctl("-j", "workspaces").catch(() => ""));
    console.error(await ctl("rollinglog").catch(() => ""));
  }
  throw error;
} finally { await stop(shell); await stop(compositor); }
