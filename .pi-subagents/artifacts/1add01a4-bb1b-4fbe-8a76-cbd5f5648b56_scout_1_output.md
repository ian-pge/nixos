# Code Context

## Files Retrieved
1. `home_manager/hyprland/quickshell/top-bar/Bar.qml` (lines 60-74, 187-368, 443-483) - layer-surface size, multi-property center animation, and retained selector trees.
2. `home_manager/hyprland/quickshell.nix` (lines 1-25) - derivation, shader compilation, active config, and systemd startup.
3. `home_manager/hyprland/hyprland.nix` (lines 1-18, 50-82, 150-180) - mixed-refresh monitor layout, NVIDIA/session environment, and Super+I binding.
4. `home_manager/hyprland/quickshell/top-bar/StatusData.qml` (lines 469-524, 1007-1032) - focused-monitor routing and debug transition state changes.
5. `home_manager/hyprland/quickshell/top-bar/shell.qml` (lines 3-14) - one Bar/PanelWindow is instantiated per screen while status is shared.

## Key Code

- **High — the experiment deliberately performs expensive geometry animation, not merely compositor-friendly transforms.** `Bar.qml:202-213` changes the center card from workspace dimensions to `480x560` for debug. `Bar.qml:319-353` simultaneously animates `width`, `height`, and a JS-driven `transitionProgress` for 600 ms. Width/height changes trigger layout, clipping, and layer-surface damage each frame; `contentOpacity()`/`contentOffset()` are JS functions evaluated by bindings for every retained content mode (`Bar.qml:263-314`). This is the strongest local code-level pacing candidate.

- **Medium — all center contents remain instantiated during Cmd+I.** The mode list has nine entries (`Bar.qml:214-216`), transition startup captures opacity and offset for all nine (`296-302`), and selector components remain in the clipped card with only `enabled`/opacity changed (examples `443-483`). `enabled: false` does not prevent rendering/layout by itself; invisible-at-opacity-zero subtrees can still incur binding/layout work. Debug itself has no dedicated child here: it expands an empty card and adds a 2 px border (`321-325`), making Cmd+I a useful geometry/render-loop probe rather than a realistic content benchmark.

- **Medium — a large transparent layer surface exists on both outputs.** `Bar.qml:60-74` fixes every PanelWindow at 600 logical px high and full output width, although a mask limits input. `shell.qml:8-13` creates one per screen. On the 5120-wide/1.25 output that is roughly 4096x600 logical; on the 2560/1.6 output roughly 1600x600 logical. The mask is input geometry, not evidence that scenegraph allocation/damage is similarly cropped.

- **Medium — mixed refresh rates create a plausible cross-window scheduling edge.** Repo config is DP-2 5120x2160@120 scale 1.25 and eDP-1 2560x1600@165 scale 1.6 (`hyprland.nix:15-18`). Runtime `hyprctl monitors -j` confirmed 120.000 and 165.004 Hz, both `vrr:false`, both XRGB8888. Since one Quickshell process/engine owns PanelWindows on both outputs, establish whether pacing follows the focused/target output. Cmd+I resolves to the focused monitor (`StatusData.qml:469-475`) and the non-target Bar locally maps the transition to workspaces (`Bar.qml:244-246,359-366`).

- **Low/experimental — the 600 ms Bezier is intentionally front-loaded.** `Bar.qml:328-353` uses `[0.0, 0.75, 0.15, 1.0, 1.0, 1.0]`, which can look like a burst followed by a long slow tail even with perfect frame delivery. Do not infer dropped frames from perceived uneven velocity until compared with linear easing.

- **Cmd+I path.** `hyprland.nix:178` invokes `qs --config top-bar ipc call topbar toggleDebug`. `StatusData.qml:1007-1024` targets the focused monitor, hides all other overlays, sets debug visible, then increments the shared transition serial via `beginCenterTransition`/`finishCenterTransition` (`502-524`). Each Bar receives the serial and starts its local transition (`Bar.qml:356-367`).

- **Packaging/service.** `quickshell.nix:2-10` copies the QML into an immutable derivation and compiles the border shader; `14-23` selects it and enables a user service at `graphical-session.target`. Runtime resolved `~/.config/quickshell/top-bar` to `/nix/store/0b8ky...-quickshell-top-bar` and the unit to `/nix/store/djsch...-quickshell.service/quickshell.service`, so edits in the repo are not live until activation (unless separately testing a copied config).

## Runtime and command evidence

- `pgrep -af quickshell`, `/proc/$pid/{exe,cmdline,environ}`: running `/nix/store/wzp...-quickshell-0.3.0/bin/quickshell --config top-bar`; wrapped executable is `.quickshell-wrapped`. Environment contains Wayland/Hyprland and Qt plugin paths but **no `QSG_*`, `QT_QUICK_BACKEND`, or explicit render-loop override**. Thus Qt defaults decide backend/render loop. The service inherits NVIDIA-related session values configured at `hyprland.nix:63-67` (`GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`), although the filtered process snapshot did not print those two, so inheritance should be rechecked directly before drawing a backend conclusion.
- `qs --version` and `quickshell --version`: Quickshell **0.3.0**, Nixpkgs distributed revision `tag-v0.3.0`.
- Process `QT_PLUGIN_PATH` and loaded store paths identify **Qt 6.11.1** (`qtwayland`, `qtdeclarative`, `qtbase`). `qmake6` was not installed, so direct `qmake6 -query` failed.
- `hyprctl version`: Hyprland **0.55.4**. `hyprctl monitors -j`: DP-2 120 Hz and eDP-1 165.004 Hz, VRR off, hardware cursors not in use. Repo also forces software cursors (`hyprland.nix:70-71`), which is compositor overhead but not specific to the card animation.
- `systemctl --user status quickshell.service`: active with 15 tasks; observed 156.7 MiB current / 205.8 MiB peak. Historical journal entries include two prior service runs peaking around **981-993 MiB**, an anomaly worth correlating with repeated debug/selector testing. Current helpers are GPU monitor and Python system stats. A later process snapshot immediately after a restart showed ~244 MiB RSS and 15.6% CPU over only seven seconds, so it is not steady-state evidence.
- Quickshell binary logs contain `Incubation mode changed: render loop driven` and also `Render loop does not have animation driver, animationStopped cannot be used to trigger incubation.` This confirms render-loop-driven QML incubation, but does **not** identify threaded/basic loop or OpenGL/Vulkan backend. No explicit backend/RHI/scenegraph choice was found in journal logs. Binary `.qslog` grep was noisy and should not be treated as frame-time telemetry.
- Journal shows repeated restarts during the inspection window and missing-icon warnings; no renderer crash or explicit frame-pacing warning. Repeated MPRIS warnings are unrelated background noise.

## Safe experiments (one variable at a time)

1. **Highest value:** copy the deployed config to a temporary Quickshell config and compare Cmd+I with width/height duration 600 vs 120/0 while leaving content transition intact; then invert (geometry fixed, content transition 600). This isolates layout/damage from opacity/transform animation without changing the active Nix config.
2. Compare the debug easing with `Easing.Linear`. If the perceived burst/tail disappears while frame cadence remains smooth, the Bezier—not renderer pacing—is the cause.
3. Test with only DP-2 enabled, then only eDP-1, then both; focus each before Cmd+I. Record phone slow-motion or presentation timestamps. This safely isolates mixed 120/165 Hz scheduling.
4. Temporarily reduce PanelWindow implicitHeight from 600 to the debug-required height or make debug a separate popup/window in a copied config. If the non-debug 36 px bar becomes cheaper/smoother, the always-large layer surface matters.
5. In a copied config, set non-current heavy content `visible: opacity > 0` after transitions (carefully preserving transition source/target), or use Loaders. Compare CPU/RSS and pacing. This tests retained subtree cost.
6. Launch a separate test instance from a terminal with Qt logging (`QSG_INFO=1`, `QT_LOGGING_RULES='qt.scenegraph.*=true'`) to obtain backend/render-loop evidence. Separately compare `QSG_RENDER_LOOP=threaded` and `basic`; do **not** add these globally or to the production service until results are known. A conflicting second layer shell should use a copied config/namespace and preferably stop the production unit briefly.
7. Use `WAYLAND_DEBUG=1` only for a short isolated run because output is huge; use Perfetto/sysprof or `perf stat -p PID` during repeated IPC toggles for actual CPU/wakeup evidence. Existing logs contain no frame timing.

## Architecture

Home Manager builds the QML plus precompiled shader into a Nix-store config, links it under `~/.config/quickshell/top-bar`, and starts one Quickshell process via a user systemd service. `shell.qml` owns one shared `StatusData` and creates a `Bar` PanelWindow per Quickshell screen. IPC mutates shared mode/monitor/serial state; both Bars see the serial, but only the target monitor maps to debug. Qt Quick then animates center-card geometry and JS-derived content properties on two layer surfaces presented by Hyprland to different-refresh outputs.

## Residual risks

- No frame-present timestamps or profiler trace was collected, so actual missed frames versus intentionally nonlinear motion remains unresolved.
- Backend (OpenGL vs Vulkan/software) and exact Qt render-loop implementation were not identified; only render-loop-driven incubation and absence of overrides were observed.
- Historical near-1 GiB peaks may be reload/test artifacts, retained QML state, or a leak; journal data alone cannot attribute them.
- Runtime was restarted during inspection, so the final CPU/RSS snapshot is transient.

## Start Here

Open `home_manager/hyprland/quickshell/top-bar/Bar.qml` at lines 187-368. It contains the combined 600 ms geometry, easing, and JS content transition that Cmd+I exercises.