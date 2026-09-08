# Quickshell helpers

Sources and existing tests live here. Packaging is defined in
`../../packages/quickshell.nix` and exported through `../../packages/default.nix`.
`../../home_manager/quickshell.nix` selects the commands installed in the session.
The upstream GPU monitor is packaged separately in `../../packages/gpu-usage.nix`.

`rust/` is one Cargo project with four binaries: the update checker, installer,
closure diff and brightness helper. Shared code handles JSON, locks, atomic
writes and child-process cancellation. `../../packages/quickshell-rust.nix`
builds and tests the project; `../../packages/quickshell.nix` wraps each binary
with its own runtime commands. The privileged activator remains a small shell
script, separate from the unprivileged Rust installer.

- `quickshell-update-checker` — compares the old and updated `flake.lock` JSON structurally, emits native structured JSON (`state`, `hasUpdates`, `message`, `updates`, `checkedAt`), invalidates its cache when the flake changes, atomically caches the checked candidate lock for reuse by the installer, and preserves a reboot-required state until the expected generation is running.
- `quickshell-update-diff` — reads Nix JSON format 2 closure metadata, compares package versions and emits structured changes without relying on a private third-party API.
- `quickshell-update-activator` — immutable, root-only store helper invoked through systemd `run0`; validates the system closure, registers it as the next boot generation with the native `boot` action, and restores the previous system profile if boot installation fails.
- `quickshell-update-installer` — shares the checker lock, reuses its candidate lock only while the source fingerprint still matches (otherwise it safely refreshes the lock), builds once, publishes the structured closure diff, invokes the immutable boot installer, restores the previous lockfile when installation fails, persists the reboot-required target and refreshes Quickshell over IPC.
- `quickshell-nix-cleaner` — serializes against checks and updates, runs the native `nh clean all` flow with `nh`'s own systemd `run0` elevation, keeps its verbose output out of QML in a single-run log, and reports the actual filesystem space reclaimed without parsing private output.
- `quickshell-system-stats` — persistent Python telemetry process reading `/proc`, `statvfs` and backlight sysfs directly without per-second shell subprocesses.
- `quickshell-brightness` — adjusts the requested Hyprland monitor using `brightnessctl` for the laptop panel or DDC/CI for an external display. Resolves the bus from connector, model and serial once per monitor topology; accepts Quickshell-owned state and a batch of percentage-point changes, reuses a recently verified level for two seconds and performs at most one verified write per batch. Returns monitor-tagged state for the OSD; no polling or driver overrides.
- `quickshell-gpu-monitor` — zero-copy wrapper around the upstream streaming GPU monitor with the NVIDIA library path set once outside QML.
- `quickshell-weather` — stable Quickshell-facing command around `wttrbar`.
- `quickshell-speedtest` — streams generation-tagged Ookla JSON events for the network selector and cleans up the test pipeline on cancellation.

From the repository root, build an individual command with
`nix build .#quickshellUpdateChecker` (the other attributes are listed in
`packages/quickshell.nix`). This does not activate the NixOS configuration.

Rust development uses the existing opt-in shell, with no second flake and no
global Rust toolchain. From the repository root:

```sh
nix develop .#rust
cargo test --manifest-path tools/quickshell/rust/Cargo.toml
cargo clippy --manifest-path tools/quickshell/rust/Cargo.toml --all-targets -- -D warnings
```

Inside `tools/`, the existing direnv setup selects the same shell. Home Manager
installs the wrapped binaries automatically on rebuild, including on a new
machine; Cargo and rustc are not runtime dependencies. Nix may keep build tools
in its store until garbage collection, without adding them to the session PATH.

The tests use temporary directories and fake commands: no actual flake update,
privilege elevation, boot installation or monitor write. Unit tests cover version
ordering, cache identity and transaction commit/rollback; CLI tests cover build
failures, EOF, signals, cache reuse and monitor control. Nix runs them against a
dummy store closure; local tests use `/run/current-system` only as a read-only
path fixture. The install confirmation and `@@QS_UPDATE@@` JSON protocol are
unchanged. Once privileged boot installation begins, the installer waits for
its outcome before handling cancellation, so it does not restore the lockfile
under an activation still in progress.

After `cargo test` has built the debug binaries, the older cache regression
harness can also run (Bash, jq, coreutils and grep are required):

```sh
bash tools/quickshell/update-cache_test.sh
bash tools/quickshell/clean-installer_test.sh
```

The cleaner test runs on NixOS and uses the current system's `run0` path for
validation, without invoking it.

`QS_UPDATE_CHECKER_BIN` and `QS_UPDATE_INSTALLER_BIN` can point the cache harness
at another build of the **unwrapped** Rust binaries. Production Nix wrappers
deliberately prepend real runtime tools, so they must not be used with mocks.
