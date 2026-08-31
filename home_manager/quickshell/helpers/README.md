# Quickshell helper packages

These helpers are owned by `quickshell.nix`, not Waybar.

- `quickshell-update-checker` — compares the old and updated `flake.lock` JSON structurally, emits native structured JSON (`state`, `hasUpdates`, `message`, `updates`, `checkedAt`), invalidates its cache when the flake changes, atomically caches the checked candidate lock for reuse by the installer, and preserves a reboot-required state until the expected generation is running.
- `quickshell-update-diff` — reads Nix JSON format 2 closure metadata, compares package versions and emits structured changes without relying on a private third-party API.
- `quickshell-update-activator` — immutable, root-only store helper invoked through systemd `run0`; validates the system closure, registers it as the next boot generation with the native `boot` action, and restores the previous system profile if boot installation fails.
- `quickshell-update-installer` — shares the checker lock, reuses its candidate lock only while the source fingerprint still matches (otherwise it safely refreshes the lock), builds once, publishes the structured closure diff, invokes the immutable boot installer, restores the previous lockfile when installation fails, persists the reboot-required target and refreshes Quickshell over IPC.
- `quickshell-nix-cleaner` — serializes against checks and updates, runs the native `nh clean all` flow with `nh`'s own systemd `run0` elevation, keeps its verbose output out of QML in a single-run log, and reports the actual filesystem space reclaimed without parsing private output.
- `quickshell-system-stats` — persistent Python telemetry process reading `/proc`, `statvfs` and backlight sysfs directly without per-second shell subprocesses.
- `quickshell-gpu-monitor` — zero-copy wrapper around the upstream streaming GPU monitor with the NVIDIA library path set once outside QML.
- `quickshell-weather` — stable Quickshell-facing command around `wttrbar`.
- `quickshell-speedtest` — streams generation-tagged Ookla JSON events for the network selector and cleans up the test pipeline on cancellation.

The legacy Waybar helper definitions remain intact in `../../waybar.nix`, but are installed only if Waybar is enabled.
