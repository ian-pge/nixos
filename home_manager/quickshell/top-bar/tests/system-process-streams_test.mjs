// Real stdin/stdout protocol, isolated GPU sysfs; no shell/UI/session changes.
import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {mkdtemp, mkdir, writeFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import readline from "node:readline";

const fixture = await mkdtemp(join(tmpdir(), "quickshell-process-streams-"));
const device = join(fixture, "0000:01:00.0");
await mkdir(join(device, "power"), {recursive:true});
await writeFile(join(device, "vendor"), "0x10de");
await writeFile(join(device, "class"), "0x030000");
await writeFile(join(device, "power/runtime_status"), "suspended");

async function check(binary, gpu) {
  const child = spawn(binary, gpu ? ["--sysfs-root", fixture] : [], {stdio:["pipe","pipe","pipe"]});
  const exit = new Promise(resolve => child.on("exit", (code, signal) => resolve({code,signal})));
  let stderr=""; child.stderr.on("data", data => stderr += data);
  const lines = readline.createInterface({input:child.stdout});
  const deadline = setTimeout(() => child.kill(), 20000);
  let phase=0, quiet=0, firstTopAt=0;
  try {
    for await (const line of lines) {
      const report=JSON.parse(line);
      if (phase===0) {
        assert.equal(report.top, undefined, "Closed panel must not collect process lists");
        child.stdin.write("7\n"); phase=1;
      } else if (phase===1 && report.top?.generation===7) {
        if (gpu) assert.equal(report.top.state,"sleeping");
        else { assert.equal(report.top.cpu,null); assert.ok(Array.isArray(report.top.memory)); }
        child.stdin.write("7\n"); // Same subscription must preserve the CPU baseline.
        firstTopAt=Date.now(); phase=2;
      } else if (phase===2 && report.top?.generation===7) {
        assert.ok(Date.now()-firstTopAt >= 1800, "Top polling exceeded the 2 s cadence");
        if (!gpu) assert.ok(Array.isArray(report.top.cpu));
        child.stdin.write("0\n"); phase=3;
      } else if (phase===3 && report.top===undefined) {
        if (++quiet===2) { child.stdin.write("9\n"); phase=4; }
      } else if (phase===4 && report.top?.generation===9) {
        if (!gpu) assert.equal(report.top.cpu,null, "Reopening must reset the CPU baseline");
        child.stdin.end(); quiet=0; phase=5;
      } else if (phase===5 && report.top===undefined) {
        if (++quiet===2) { phase=6; child.stdout.destroy(); break; }
      }
    }
    const result=await exit;
    assert.equal(phase,6, `Incomplete protocol test (${phase}): ${stderr}`);
    assert.equal(result.code,0,stderr);
    console.log(`PASS: ${gpu ? "GPU" : "CPU/RAM"} disabled by default, generation control, 2 s cadence, close/reopen, EOF and pipe cleanup`);
  } finally {
    clearTimeout(deadline);
    if (child.exitCode===null && child.signalCode===null) child.kill();
    await exit;
  }
}
try {
  await Promise.all([
    check(process.argv[2] || fileURLToPath(new URL("../../../../tools/quickshell/system-stats/target/debug/quickshell-system-stats", import.meta.url)), false),
    check(process.argv[3] || fileURLToPath(new URL("../../../../tools/quickshell/gpu-monitor/target/debug/quickshell-gpu-monitor", import.meta.url)), true),
  ]);
} finally {
  await rm(fixture,{recursive:true,force:true});
}
