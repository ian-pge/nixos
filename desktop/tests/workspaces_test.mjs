// Native Quickshell integration test with private Hyprland IPC sockets.
// Requires only node and qs. No windows, dispatches or audio on the real desktop.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, mkdir, rm } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const directory = path.dirname(fileURLToPath(import.meta.url));
const runtime = await mkdtemp(path.join(os.tmpdir(), "quickshell-workspace-ipc-"));
const signature = "quickshell-workspace-test";
const socketDirectory = path.join(runtime, "hypr", signature);
await mkdir(socketDirectory, { recursive: true });

const monitors = [
  { id: 0, name: "DP-2", description: "Dell", activeWorkspace: { id: 3, name: "3" }, focused: true },
  { id: 1, name: "eDP-1", description: "Laptop", activeWorkspace: { id: 5, name: "5" }, focused: false },
].map(monitor => ({ ...monitor, x: 0, y: 0, width: 1920, height: 1080, scale: 1,
  specialWorkspace: { id: 0, name: "" } }));
const workspaces = Array.from({ length: 8 }, (_, index) => ({
  id: index + 1, name: String(index + 1), monitor: index < 4 ? "DP-2" : "eDP-1",
  monitorID: index < 4 ? 0 : 1, windows: 0, hasfullscreen: false,
}));
const eventClients = new Set();
const requestedWorkspaces = [];
let monitorRequests = 0;
let child;
let serverError;
const events = net.createServer(socket => {
  eventClients.add(socket);
  socket.on("close", () => eventClients.delete(socket));
});
const requests = net.createServer(socket => {
  socket.once("data", data => {
    try {
      const request = data.toString();
      if (request === "j/status") return socket.end(JSON.stringify({ configProvider: "lua" }));
      if (request === "j/monitors") {
        monitorRequests++;
        return socket.end(JSON.stringify(monitors));
      }
      if (request === "j/workspaces") return socket.end(JSON.stringify(workspaces));
      if (request === "j/clients") return socket.end("[]");
      assert.match(request, /^dispatch hl\.dsp\.focus\(\{ workspace = [1-8] \}\)$/);
      const id = Number(request.match(/workspace = (\d+)/)[1]);
      requestedWorkspaces.push(id);
      const source = monitors.find(monitor => monitor.focused);
      const destination = monitors[id <= 4 ? 0 : 1];
      const workspaceChanged = destination.activeWorkspace.id !== id;
      destination.activeWorkspace = { id, name: String(id) };
      for (const monitor of monitors) monitor.focused = monitor === destination;
      // The critical ordering: Quickshell still considers source focused when
      // workspacev2 arrives, so it overwrites source.activeWorkspace with id.
      let event = workspaceChanged ? `workspace>>${id}\nworkspacev2>>${id},${id}\n` : "";
      if (destination !== source) event += `focusedmon>>${destination.name},${id}\n`;
      for (const client of eventClients) client.write(event);
      socket.end("ok");
    } catch (error) {
      serverError = error;
      socket.end("test fixture error");
      child?.kill();
    }
  });
});

try {
  await Promise.all([
    new Promise(resolve => events.listen(path.join(socketDirectory, ".socket2.sock"), resolve)),
    new Promise(resolve => requests.listen(path.join(socketDirectory, ".socket.sock"), resolve)),
  ]);
  child = spawn("qs", ["-p", path.join(directory, "./tst_WorkspaceIpc.qml"), "--no-color"], {
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, XDG_RUNTIME_DIR: runtime, HYPRLAND_INSTANCE_SIGNATURE: signature,
      WAYLAND_DISPLAY: "", QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
      QT_NO_XDG_DESKTOP_PORTAL: "1", QUICKSHELL_WORKSPACE_TEST: "1" },
  });
  let output = "";
  for (const stream of [child.stdout, child.stderr]) stream.on("data", data => {
    output += data;
    process.stdout.write(data);
  });
  const timeout = setTimeout(() => child.kill(), 20000);
  let exitCode;
  try {
    exitCode = await new Promise((resolve, reject) => {
      child.on("error", reject);
      child.on("exit", resolve);
    });
  } finally {
    clearTimeout(timeout);
  }
  if (serverError) throw serverError;
  assert.equal(exitCode, 0, "Quickshell integration tests must complete successfully");
  assert.match(output, /WorkspaceIpc: \d+ passed, 0 failed/);
  assert.doesNotMatch(output, /Binding loop|TypeError|ReferenceError/);
  assert.deepEqual(requestedWorkspaces, [6, 7, 3, 2, 5, 4]);
  assert.ok(monitorRequests >= 7, "Every switch must refresh the authoritative monitor snapshots");
  console.log("PASS: isolated native IPC, both switch directions, focus-only and same-monitor changes");
} finally {
  for (const client of eventClients) client.destroy();
  await Promise.all([events, requests].map(server => new Promise(resolve => server.close(resolve))));
  await rm(runtime, { recursive: true, force: true });
}
