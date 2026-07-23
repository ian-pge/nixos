# Quickshell helper packages

These helpers are owned by `quickshell.nix`, not Waybar.

- `quickshell-update-checker` — emits native structured JSON (`hasUpdates`, `message`, `updates`, `checkedAt`), uses an XDG cache, atomic writes and `flock` to prevent concurrent Nix checks.
- `quickshell-update-installer` — updates the flake, runs `nh os switch`, writes the native cache schema and refreshes Quickshell over IPC.
- `quickshell-system-stats` — persistent Python telemetry process reading `/proc`, `statvfs` and backlight sysfs directly without per-second shell subprocesses.
- `quickshell-gpu-monitor` — zero-copy wrapper around the upstream streaming GPU monitor with the NVIDIA library path set once outside QML.
- `quickshell-weather` — stable Quickshell-facing command around `wttrbar`.

The legacy Waybar helper definitions remain intact in `../../waybar.nix`, but are installed only if Waybar is enabled.
