# Quickshell helper packages

These helpers are owned by `quickshell.nix`, not Waybar.

- `quickshell-update-checker` — compares the old and updated `flake.lock` JSON structurally, emits native structured JSON (`state`, `hasUpdates`, `message`, `updates`, `checkedAt`), and uses an XDG cache, atomic writes and `flock`.
- `quickshell-update-installer` — shares the checker lock, restores the previous lockfile when `nh os switch` fails, writes the native cache schema and refreshes Quickshell over IPC.
- `quickshell-system-stats` — persistent Python telemetry process reading `/proc`, `statvfs` and backlight sysfs directly without per-second shell subprocesses.
- `quickshell-gpu-monitor` — zero-copy wrapper around the upstream streaming GPU monitor with the NVIDIA library path set once outside QML.
- `quickshell-weather` — stable Quickshell-facing command around `wttrbar`.
- `quickshell-speedtest` — streams generation-tagged Ookla JSON events for the network selector and cleans up the test pipeline on cancellation.

The legacy Waybar helper definitions remain intact in `../../waybar.nix`, but are installed only if Waybar is enabled.
