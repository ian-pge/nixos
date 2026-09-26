# Local tools

Each logical tool owns its sources and tests in `tools/<name>/` and its Nix
recipe in `packages/<name>.nix`. Quickshell tools are grouped under
`tools/quickshell/<name>/` and `packages/quickshell/<name>.nix`.
`packages/default.nix` exports the final
commands through `localPackages`; Home Manager selects what to install.

| Sources | Nix recipe | Commands |
| --- | --- | --- |
| `hyprlock-age/` | `hyprlock-age.nix` | Fractional age for Hyprlock |
| `quickshell/update/` | `quickshell/update.nix` | Update checker, installer, closure diff and privileged activator |
| `quickshell/brightness/` | `quickshell/brightness.nix` | Internal backlight and external DDC/CI brightness |
| `quickshell/nix-cleaner/` | `quickshell/nix-cleaner.nix` | Native `nh clean all` integration |
| `quickshell/system-stats/` | `quickshell/system-stats.nix` | Persistent Rust CPU, RAM, disk and backlight telemetry |
| `quickshell/gpu-monitor/` | `quickshell/gpu-monitor.nix` | Persistent Rust NVIDIA telemetry through NVML, with runtime-suspend checks |
| `quickshell/chrome-tabs/` | `quickshell/chrome-tabs.nix` | Rust TabCtl adapter and local SQLite favicon cache |
| `quickshell/speedtest/` | `quickshell/speedtest.nix` | Generation-tagged Ookla JSON streaming and cancellation |
| `quickshell/weather/` | `quickshell/weather.nix` | Rust automatic location, current temperature and daily calendar weather |
| `quickshell/beeper/` | `quickshell/beeper.nix` | Persistent Go Beeper API client, drafts, media and local notifications |
| `../desktop/features/messenger/` | `quickshell/beeper-preview.nix` | Standalone messenger design preview with fictional conversations |

The QML application lives in [`../desktop/`](../desktop/README.md); backend
sources stay here. `packages/quickshell/runtime.nix` supplies the shared wrapped
Quickshell runtime, and `desktop.nix` packages the QML sources. Home Manager only
installs, configures and starts them; the preview uses that same runtime.

The GPU collector lives in `quickshell/gpu-monitor/` and directly loads the
NVIDIA driver's NVML library; no upstream GPU executable or wrapper is needed.
The Chrome tab integration and favicons live in `quickshell/chrome-tabs/`;
`home_manager/tabctl.nix` installs the commands and registers the native host.

The Rust projects are independent Cargo packages, each with its own lockfile.
Update checker, installer and diff share one project because they form one
update workflow. Its privileged shell activator is packaged separately in the
same Nix recipe. Only final commands are exported; the intermediate Rust build
is internal to the recipe.

All Rust projects use the existing development shell:

```sh
# From the repository root:
nix develop .#rust
cargo test --manifest-path tools/quickshell/update/Cargo.toml
cargo test --manifest-path tools/quickshell/brightness/Cargo.toml
cargo test --manifest-path tools/quickshell/system-stats/Cargo.toml
cargo test --manifest-path tools/quickshell/gpu-monitor/Cargo.toml
cargo test --manifest-path tools/quickshell/chrome-tabs/Cargo.toml
cargo test --manifest-path tools/quickshell/weather/Cargo.toml
```

The system and GPU collectors share the central panel's demand-driven stdin
protocol: process top fives are collected every two seconds only while the
panel is visible; the ordinary bubble telemetry continues every second.
After building both Cargo binaries, run
`node desktop/tests/system-process-streams_test.mjs`
from the repository root to check subscription, cadence and pipe lifetime.

The existing `tools/.envrc` selects that shell when direnv is enabled. There is
one repository flake and a shared Rust development environment. A NixOS rebuild
installs the selected commands automatically, including on a new machine.
Cargo and rustc are build tools, not runtime dependencies; Nix may keep them
in its store until garbage collection without adding them to the session PATH.

Build commands individually with `nix build .#quickshellUpdateChecker` or
`nix build .#quickshellBrightness`; see `packages/default.nix` and
`packages/quickshell/update.nix` for the exported attributes. These builds do
not activate the NixOS configuration.

The Beeper backend is an independent Go module with pinned `go.mod` and
`go.sum`. Its project `.envrc` selects `nix develop .#go`, which provides Go,
gopls, Delve and golangci-lint without installing a global compiler. From the
repository root:

```sh
nix develop .#go
cd tools/quickshell/beeper
go test ./...
go build .
```

Build the installed, wrapped executable with `nix build .#quickshellBeeper`.
Its wrapper supplies `secret-tool`, `wl-paste` and `xdg-open` at runtime;
credentials stay in the system keyring. Source filtering includes only Go
sources and module lockfiles, so local drafts and attachments cannot enter the
Nix store. When dependencies change, set `vendorHash` in the Nix recipe to
`lib.fakeHash`, build once, then replace it with the dependency hash reported
by Nix. Home Manager launches one persistent
backend through Quickshell; hiding the messenger does not stop notifications.
For a local design review without Beeper, credentials, or a desktop rebuild,
run `nix run .#quickshellBeeperPreview`. The preview uses the same QML components
with fictional conversations and has no backend process.

The messenger QML graph can also be compiled against a real Wayland backend
without changing the desktop or connecting to Beeper:

```sh
node desktop/tests/messenger-wayland_test.mjs /path/to/packaged/quickshell
```

Run this from the repository root with Node.js, Hyprland and D-Bus available
(the `cpp` development shell supplies Node.js and Hyprland). The Quickshell
executable must include the configured Qt Multimedia and Liquid Glass imports.
The harness starts a minimal nested compositor and a private bus without desktop
service activation, compiles the actual bar graph, then removes its temporary
session. It does not load a compositor plugin or instantiate the messenger.

Additional regression harnesses, after Cargo has built the update binaries:

```sh
bash tools/quickshell/update/update-cache_test.sh
bash tools/quickshell/nix-cleaner/clean-installer_test.sh
```

The harnesses need Bash, jq, coreutils and grep. The cleaner also uses
util-linux and the current NixOS system's `run0` path for validation, without
invoking it. Tests use isolated files and fake commands.

The [glass shape viewer](liquid-glass/viewer/README.md) has a separate
`nix develop .#threejs` environment (Node.js/npm), alongside the `cpp` shell
used by the compositor plugin. Its Three.js/Vite dependencies are project-local
and locked with npm. It is a local browser tool, not installed into the system.
