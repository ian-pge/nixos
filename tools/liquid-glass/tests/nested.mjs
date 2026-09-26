// Run only a private, nested compositor. No plugin is loaded into the desktop.
import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readdir, readFile, copyFile, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";

const here = path.dirname(fileURLToPath(import.meta.url));
const plugin = path.resolve(process.argv[2] || path.join(here, "../build/libliquid-glass.so"));
// Nix dev shells can put TMPDIR under a long /tmp/nix-shell.* path. Hyprland's
// event-socket name then exceeds the Unix socket limit even though IPC1 works.
const runtime = await mkdtemp("/tmp/gl-");
const parentDisplay = path.resolve(process.env.XDG_RUNTIME_DIR, process.env.WAYLAND_DISPLAY);
const env = {...process.env, XDG_RUNTIME_DIR: runtime, WAYLAND_DISPLAY: parentDisplay,
    QSG_RENDER_LOOP: "threaded",
    HYPRLAND_NO_SD_VARS: "1", HYPRLAND_NO_SD_NOTIFY: "1", HYPRLAND_NO_SD_TARGET: "1",
    HYPRLAND_NO_RT: "1", AQ_DRM_DEVICES: "/dev/null", AQ_NO_MODIFIERS: "1"};
delete env.HYPRLAND_INSTANCE_SIGNATURE;
delete env.NOTIFY_SOCKET;
let compositor, scene, widget;
let log = "", sceneLog = "";
const exec = promisify(execFile);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function ppm(bytes) {
    const header = /^P6\s+(\d+)\s+(\d+)\s+255\s/.exec(bytes.toString("ascii", 0, 100));
    assert.ok(header, "Expected PPM screenshot");
    const width = Number(header[1]);
    const height = Number(header[2]);
    const pixel = (x, y) => bytes.subarray(header[0].length + (y*width + x)*3, header[0].length + (y*width + x)*3 + 3);
    return Object.assign(pixel, {width, height});
}
async function until(predicate, description) {
    for (let i = 0; i < 200; i++) {
        if (await predicate()) return;
        await delay(50);
    }
    throw new Error("Timeout: " + description);
}
async function stop(child) {
    if (!child) return;
    try { process.kill(-child.pid, "SIGTERM"); } catch {}
    await delay(200);
    try { process.kill(-child.pid, "SIGKILL"); } catch {}
    child.stdout?.destroy(); child.stderr?.destroy();
}
try {
    compositor = spawn("Hyprland", ["--config", path.join(here, "hyprland.lua")], {env, detached:true});
    for (const stream of [compositor.stdout, compositor.stderr]) stream.on("data", data => { log += data; });
    await until(async () => {
        if (compositor.exitCode !== null) throw new Error("Nested Hyprland exited: " + compositor.exitCode);
        const names = await readdir(path.join(runtime, "hypr")).catch(() => []);
        if (!names.length) return false;
        const display = (await readdir(runtime)).find(name => /^wayland-\d+$/.test(name));
        if (!display) return false;
        env.HYPRLAND_INSTANCE_SIGNATURE = names[0];
        env.WAYLAND_DISPLAY = display;
        try {
            const monitors = JSON.parse((await exec("hyprctl", ["-j", "monitors"], {env})).stdout);
            return monitors.some(m => m.width > 0 && m.height > 0);
        } catch { return false; }
    }, "nested Hyprland readiness");
    // Optional stabilization of OUR private compositor window only. Tiling on
    // the parent can otherwise resize the scene midway through pixel checks.
    if (process.env.GLASS_TEST_FLOAT === "1") {
        let client;
        await until(async () => {
            const clients = JSON.parse((await exec("hyprctl", ["-j", "clients"])).stdout);
            client = clients.find(c => c.pid === compositor.pid && c.mapped);
            return !!client;
        }, "private compositor's parent window");
        const selector = JSON.stringify("address:" + client.address);
        if (!client.floating)
            await exec("hyprctl", ["dispatch", `hl.dsp.window.float({window=${selector}})`]);
        await exec("hyprctl", ["dispatch", `hl.dsp.window.resize({window=${selector},x=1280,y=800})`]);
        await delay(700);
    }
    const ctl = async (...args) => (await exec("hyprctl", args, {env})).stdout;
    assert.equal((await ctl("configerrors")).trim(), "", "Test compositor configuration must be valid");
    // Native notification rendering after our pass used to mask GL-cache bugs.
    await ctl("dismissnotify", "-1");
    const loaded = await ctl("plugin", "load", plugin);
    assert.match(loaded, /ok/i, loaded);
    console.log("Plugin loaded into the isolated compositor");
    scene = spawn("qs", ["-p", path.join(here, "scene.qml")], {env, detached:true});
    for (const stream of [scene.stdout, scene.stderr]) stream.on("data", data => { sceneLog += data; });
    let status;
    await until(async () => {
        if (compositor.exitCode !== null) throw new Error("Nested compositor exited during rendering: " + compositor.exitCode);
        try { status = JSON.parse(await ctl("liquidglass")); return status.frames >= 10 || !status.enabled; } catch { return false; }
    }, "glass frames");
    assert.equal(status.enabled, true, JSON.stringify(status));
    const widgetConfig = path.resolve(here, "../../../desktop/glass-test.qml");
    const widgetEnv = {...env, LIQUID_GLASS_TEST:"1"};
    widget = spawn("qs", ["-p", widgetConfig], {env:widgetEnv, detached:true});
    for (const stream of [widget.stdout, widget.stderr]) stream.on("data", data => { sceneLog += data; });
    const isGlass = async () => (await exec("qs", ["ipc", "-p", widgetConfig, "call", "glass-test", "enabled"], {env})).stdout.trim();
    await until(async () => { try { return await isGlass() === "true"; } catch { return false; } }, "real widget glass state");
    const before = status.frames;
    await delay(1000);
    status = JSON.parse(await ctl("liquidglass"));
    assert.ok(status.frames > before + 10, "Live background must repaint through the glass");
    const optimized = typeof status.contentUpdates === "number";
    if (typeof status.blurUpdates === "number")
        assert.equal(status.blurUpdates, status.backgroundCopies, "Blur must be refreshed with each new backdrop");
    const analytic = typeof status.analyticFrames === "number" && process.env.LIQUID_GLASS_DISABLE_GEOMETRY !== "1";
    if (analytic && typeof status.profileUpdates === "number") {
        assert.ok(status.profileUpdates > 0 && status.profileUpdates < 15, "Static cushion profiles must be cached");
        assert.equal(status.profile, "cushion");
    }
    if (optimized) {
        assert.ok(status.contentUpdates < status.frames / 4, "Static QML content and its mask must be cached");
        assert.ok(status.copiedPixels < status.referencePixels * 0.75, "Backdrop copies must be region-limited");
        console.log("Work reduction:", Math.round(100 * (1 - status.copiedPixels / status.referencePixels))
            + "% fewer copied pixels;", status.contentUpdates, "content updates /", status.frames, "passes");
    }
    if (analytic)
        assert.ok(status.analyticFrames > status.frames * 0.8, "Real surface geometry must replace the raster mask");
    else if (typeof status.analyticFrames === "number")
        assert.equal(status.analyticFrames, 0, "The raster fallback must not require the geometry extension");
    const output = JSON.parse(await ctl("-j", "monitors"))[0].name;
    if (process.env.GLASS_TEST_GRIM) {
        await exec("qs", ["ipc", "-p", path.join(here, "scene.qml"), "call", "glass-scene", "freeze"], {env});
        await delay(200);
        await exec(process.env.GLASS_TEST_GRIM, ["-o", output,
            process.env.GLASS_TEST_IMAGE || "/tmp/liquid-glass-desktop-test.png"], {env});
        await exec(process.env.GLASS_TEST_GRIM, ["-o", output, "-t", "ppm", path.join(runtime, "glass.ppm")], {env});
        if (process.env.GLASS_TEST_PPM) await copyFile(path.join(runtime, "glass.ppm"), process.env.GLASS_TEST_PPM);
        // The parent compositor can resize our nested window below 1280 px.
        // Keep both cursor positions and the comparison area on the output.
        const frame = ppm(await readFile(path.join(runtime, "glass.ppm")));
        const cursorX = Math.min(1050, frame.width - 180), cursorY = Math.min(600, frame.height - 180);
        await ctl("dispatch", `hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})`);
        await delay(120);
        await exec(process.env.GLASS_TEST_GRIM, ["-c", "-o", output, "-t", "ppm", path.join(runtime, "cursor-a.ppm")], {env});
        await ctl("dispatch", `hl.dsp.cursor.move({x=${cursorX + 80},y=${cursorY + 50}})`);
        await delay(120);
        await exec(process.env.GLASS_TEST_GRIM, ["-c", "-o", output, "-t", "ppm", path.join(runtime, "cursor-b.ppm")], {env});
        const a = ppm(await readFile(path.join(runtime, "cursor-a.ppm")));
        const b = ppm(await readFile(path.join(runtime, "cursor-b.ppm")));
        let cursorPixels = 0;
        for (let y = cursorY - 10; y < cursorY + 40; y++) for (let x = cursorX - 10; x < cursorX + 50; x++) {
            if (a(x,y).some((channel, i) => Math.abs(channel - b(x,y)[i]) > 30)) cursorPixels++;
        }
        console.log("Visible software cursor:", cursorPixels, "changed pixels");
        assert.ok(cursorPixels >= 20, "Software cursor must remain visible after the glass render pass");
        if (optimized) {
            if (analytic) {
                await exec("qs", ["ipc", "-p", widgetConfig, "call", "glass-test", "activate", "true"], {env});
                await delay(250);
                const start = JSON.parse(await ctl("liquidglass"));
                await delay(500);
                const moving = JSON.parse(await ctl("liquidglass"));
                if (typeof moving.profileUpdates === "number")
                    assert.ok(moving.profileUpdates - start.profileUpdates <= 2,
                        "Uniform capsule bounce must reuse its cushion profile: " + (moving.profileUpdates - start.profileUpdates));
                assert.ok(moving.analyticFrames > start.analyticFrames + 10, "Animated capsule geometry must reach the renderer");
                assert.ok(moving.rasterFrames - start.rasterFrames < 3, "Animated geometry must stay matched to its buffer");
                await exec("qs", ["ipc", "-p", widgetConfig, "call", "glass-test", "activate", "false"], {env});
                await delay(400);
            }
            // Move/resize a real layer surface, then return to the same place.
            // Its previous extent must be cleaned, and the restored picture
            // must not accumulate refraction from previous frames.
            const geometry = async (...values) => exec("qs", ["ipc", "-p", widgetConfig,
                "call", "glass-test", "geometry", ...values.map(String)], {env});
            await geometry(400, 180, 310);
            await delay(180);
            await geometry(250, 40, 260);
            await delay(200);
            await exec(process.env.GLASS_TEST_GRIM, ["-o", output, "-t", "ppm", path.join(runtime, "restored.ppm")], {env});
            const restored = ppm(await readFile(path.join(runtime, "restored.ppm")));
            assert.deepEqual([restored.width, restored.height], [frame.width, frame.height],
                "The parent resized the nested output during the comparison; rerun with stable window geometry");
            let changed = 0, pixels = 0;
            for (let y = 230; y < 450; y++) for (let x = Math.max(720, frame.width - 520); x < frame.width - 10; x++) {
                pixels++;
                if (frame(x, y).some((c, i) => Math.abs(c - restored(x, y)[i]) > 4)) changed++;
            }
            assert.ok(changed < Math.max(10, pixels * 0.003), "Moving glass must leave no trails: " + changed);
            console.log("Move/resize restoration:", changed, "changed pixels /", pixels);
        }
    }
    console.log("Live rendering:", status);
    if (optimized) {
        assert.match(await ctl("liquidglass", "disable"), /ok/i);
        await until(async () => await isGlass() === "false", "opaque fallback after disable");
        const disabled = JSON.parse(await ctl("liquidglass"));
        assert.equal(disabled.enabled, false);
        await until(async () => JSON.parse(await ctl("liquidglass")).surfaces === 0, "cached textures released after disable");
        await delay(150);
        assert.equal(JSON.parse(await ctl("liquidglass")).frames, disabled.frames, "Disabled glass must not render");
        assert.match(await ctl("liquidglass", "enable"), /ok/i);
        await until(async () => await isGlass() === "true", "glass re-enable");
        console.log("Runtime disable/enable and opaque fallback: PASS");
    }
    console.log("Unload:", (await ctl("plugin", "unload", plugin)).trim());
    await until(async () => await isGlass() === "false", "opaque fallback after plugin unload");
    if (process.env.GLASS_TEST_GRIM) {
        await exec(process.env.GLASS_TEST_GRIM, ["-o", output, "-t", "ppm", path.join(runtime, "plain.ppm")], {env});
        const glass = ppm(await readFile(path.join(runtime, "glass.ppm")));
        const plain = ppm(await readFile(path.join(runtime, "plain.ppm")));
        function peak(image) {
            let best = -1, position = 0;
            for (let x = 35; x < 50; x++) {
                const p = image(x, 55);
                const luminance = p[0] + p[1] + p[2];
                if (luminance > best) { best = luminance; position = x; }
            }
            return position;
        }
        const displacement = Math.abs(peak(glass) - peak(plain));
        assert.ok(displacement >= 1, "The background stripe must be displaced by the glass rim");
        function interiorPeak(image, x, from, to) {
            let best = -1, position = 0;
            for (let y = from; y <= to; y++) {
                const luminance = image(x, y).reduce((sum, c) => sum + c, 0);
                if (luminance > best) { best = luminance; position = y; }
            }
            return position;
        }
        // Sample horizontal grid lines well outside the 20 px rim, including
        // a point >128 px inside the large panel (the old propagation limit).
        const interior = [[510, 150, 195], [250, 445, 492]].map(([x, from, to]) =>
            Math.abs(interiorPeak(glass, x, from, to) - interiorPeak(plain, x, from, to)));
        assert.ok(interior.every(d => d >= 4), "Refraction must remain visible deep inside both panels: " + interior);
        // Average a text-free patch: a single pixel may land on a refracted
        // bright grid line when the lens profile changes.
        const brightness = image => {
            let sum = 0;
            for (let y = 575; y < 640; y++) for (let x = 280; x < 335; x++)
                sum += image(x, y).reduce((total, c) => total + c, 0);
            return sum;
        };
        const transmission = brightness(glass) / brightness(plain);
        assert.ok(transmission < 0.65 && transmission > 0.2,
            "The smoke must be dark but still translucent: " + transmission);
        let white = 0, preserved = 0;
        for (let y = 45; y < 66; y++) for (let x = 95; x < 178; x++) {
            const p = plain(x, y), g = glass(x, y);
            // Only fully opaque glyph cores: antialiased edges legitimately
            // blend with the new background and need not have identical RGB.
            if ([...p].every(c => c === 255)) {
                white++;
                if (p.every((c, channel) => Math.abs(c - g[channel]) <= 3)) preserved++;
            }
        }
        console.log("Pixel checks:", displacement, "px rim;", interior, "px interior;",
            Math.round(transmission * 100) + "% brightness;", preserved, "/", white, "text pixels preserved");
        assert.ok(white > 10 && preserved / white > 0.98, "Opaque text must remain sharp and unmoved");
    }
    assert.match(await ctl("plugin", "load", plugin), /ok/i);
    await until(async () => await isGlass() === "true", "plugin reload");
    if (analytic)
        await until(async () => JSON.parse(await ctl("liquidglass")).analyticFrames >= 4, "geometry reconnected after plugin reload");
    assert.match(await ctl("output", "create", "wayland", "GLASS-TEST"), /ok/i);
    await ctl("eval", 'hl.monitor({output="GLASS-TEST",mode="1280x800@60",position="auto",scale=1.25})');
    await until(async () => JSON.parse(await ctl("liquidglass")).surfaces >= 3, "second monitor");
    await delay(200);
    if (optimized) {
        await ctl("eval", 'hl.monitor({output="GLASS-TEST",mode="1280x800@60",position="auto",scale=1.25,transform=1})');
        await until(async () => JSON.parse(await ctl("-j", "monitors")).some(m => m.name === "GLASS-TEST" && m.transform === 1),
            "rotated mixed-scale output");
        await delay(250);
        assert.equal(JSON.parse(await ctl("liquidglass")).enabled, true, "Rotated output must retain its conservative rendering path");
        if (process.env.GLASS_TEST_GRIM)
            await exec(process.env.GLASS_TEST_GRIM, ["-o", "GLASS-TEST", "/tmp/liquid-glass-rotated-test.png"], {env});
    }
    await ctl("output", "remove", "GLASS-TEST");
    await until(async () => JSON.parse(await ctl("liquidglass")).surfaces === 2, "removed output resources");
    if (optimized) {
        const sceneCall = async (...args) => (await exec("qs", ["ipc", "-p", path.join(here, "scene.qml"),
            "call", "glass-scene", ...args], {env})).stdout.trim();
        await sceneCall("freeze");
        await sceneCall("traffic", "true");
        await until(async () => JSON.parse(await ctl("liquidglass")).surfaces === 1, "only the small glass fixture remains");
        await delay(500); // Let the buffer-age damage history settle.
        await ctl("liquidglass", "reset-stats");
        const ticks = Number(await sceneCall("ticks"));
        await delay(800);
        const idle = JSON.parse(await ctl("liquidglass"));
        assert.ok(Number(await sceneCall("ticks")) > ticks + 10, "The unrelated surface must actually animate");
        assert.ok(idle.backgroundCopies <= 2 && idle.contentUpdates === 0,
            "Unrelated animation must reuse glass caches: " + JSON.stringify(idle));
        console.log("Unrelated animation:", idle.backgroundCopies, "backdrop copies;", idle.contentUpdates, "content updates");
        if (typeof idle.blurUpdates === "number")
            assert.ok(idle.blurUpdates <= 2, "Unchanged backdrops must reuse the blurred texture");
        if (typeof idle.profileUpdates === "number")
            assert.equal(idle.profileUpdates, 0, "Unrelated animation must not rebuild pebble geometry");
        await sceneCall("traffic", "false");
        await until(async () => JSON.parse(await ctl("liquidglass")).surfaces === 2, "glass restored after unrelated animation");
    }
    assert.match(await ctl("plugin", "unload", plugin), /ok/i);
    await delay(300);
    assert.equal(compositor.exitCode, null, "Unloading must not crash Hyprland");
    assert.doesNotMatch(sceneLog, /Failed to load configuration|ReferenceError|TypeError/);
    console.log("PASS: live backdrop, real Quickshell capsule, mixed-scale hotplug, unload/reload and opaque fallback");
} catch (error) {
    console.error(log.slice(-12000));
    if (env.HYPRLAND_INSTANCE_SIGNATURE) {
        const renderLog = await readFile(path.join(runtime, "hypr", env.HYPRLAND_INSTANCE_SIGNATURE, "hyprland.log"), "utf8").catch(() => "");
        console.error(renderLog.slice(-8000));
    }
    console.error(sceneLog.slice(-3000));
    throw error;
} finally {
    await stop(widget); await stop(scene); await stop(compositor);
    await rm(runtime, {recursive:true, force:true});
}
