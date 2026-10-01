# Desktop shell

This directory contains the Quickshell application. Start here for setup,
commands and source locations; the [design guide](docs/DESIGN_GUIDE.md) records
cross-component constraints, design reasons and known regressions. Exact colors,
sizes, timings and key bindings belong in their source files, not duplicate
reference tables.

## Source layout and responsibilities

| Location | Responsibility |
|---|---|
| [shell.qml](shell.qml) | One set of domain controllers and a bar per screen |
| [shell/](shell/) | Presentation, focus, IPC and messenger surfaces |
| [bar/](bar/) | Bar layout and central capsule transitions |
| [features/](features/) | Domain state and views, grouped by feature |
| [ui/](ui/) | Theme and reusable visual/input components |
| [tests/](tests/), [previews/](previews/) | Isolated regression fixtures and visual previews |
| [tools/](../tools/README.md) | Go/Rust/script helpers and their own protocol documentation |
| [packages/quickshell/](../packages/quickshell/) | Runtime dependencies, source filtering and pinned helper paths |
| [home_manager/quickshell.nix](../home_manager/quickshell.nix) | Installation and user-service configuration |

The installed config is `top-bar`, the IPC target is `topbar`, and the service
is `quickshell.service`. Runtime paths such as `quickshell/top-bar` and
`quickshell-beeper` are independent of the source layout.

## Build, preview and test

Run from the repository root:

```sh
# Build without activating the session.
nix build --no-link .#quickshellRuntime .#quickshellDesktop .#quickshellBeeperPreview

# Fictional conversations; no Beeper connection or credentials.
nix run .#quickshellBeeperPreview

# Local regressions with pinned Qt, D-Bus and backend dependencies.
nix develop .#desktop -c node desktop/tests/run.mjs

# Real Wayland object graph in a private nested compositor.
nix develop .#desktop -c node desktop/tests/messenger-wayland_test.mjs qs --desktop
```

Use the wrapped runtime, which supplies Liquid Glass, Qt Multimedia, SVG and
image-format plugins. The `desktop` shell sets `QMLTESTRUNNER` and
`BEEPER_TEST_BACKEND`; the runner reports optional skips. It is a local runner,
not a flake check or CI job. If dependencies are already available:

```sh
quickshell_runtime=$(nix build --no-link --print-out-paths .#quickshellRuntime)
node desktop/tests/run.mjs "$quickshell_runtime/bin/quickshell"
```

The Wayland harness needs an existing Wayland session, Hyprland and D-Bus.
Without `--desktop` it only compiles the graph; with it, the real composition
runs with `servicesEnabled: false`. Do not launch a second `shell.qml` merely
to test compilation: that starts real helpers and services. Controller fixtures
inject providers and fake transports; update/auth tests must never invoke a
real installer, cleaner or Polkit challenge.

Useful targeted checks:

```sh
nix develop .#desktop -c bash desktop/tests/notifications_test.sh
nix develop .#desktop -c node desktop/tests/messenger-wayland_test.mjs qs --video
nix develop .#desktop -c node desktop/tests/messenger-wayland_test.mjs qs --sidebar
nix develop .#desktop -c node desktop/tests/messenger-wayland_test.mjs qs --performance
git diff --check
```

The notification launcher uses a private bus and silent fake audio; do not run
its QML fixture on the session bus. Sidebar/performance timings are diagnostics,
not portable pass/fail thresholds. `BEEPER_SIDEBAR_SOURCE` and
`BEEPER_PERFORMANCE_SOURCE` can point to older packaged components for comparison.
Other render modes are documented at the top of the Wayland harness.
`QS_TEST_GLASS_PLUGIN=/path/to/libliquid-glass.so` loads Liquid Glass in the
private compositor. With `--desktop`, also set `QS_TEST_GRIM=/path/to/grim` and
`QS_TOOLTIP_DIAGNOSTIC=/tmp/tooltip.png` to capture the percentage tooltip using
native pointer motion. This exercises the compositor's geometry clipping.
Backend build/test commands live in each [tool's README](../tools/README.md).

## Activation and diagnostics

Workspace digits adapt to the connected displays: Cmd+1…5 on a lone display;
with the laptop and an external screen, Cmd+1…5 targets the external display
and Cmd+6…0 targets the laptop. Disconnecting merges windows from 6…10 into
the corresponding 1…5 slots without closing applications. Cmd+Alt+H/L cycles
within the current screen's five slots. See the
[workspace policy](../home_manager/hyprland/workspace-policy.lua).

Validate the generated Lua with
`lua home_manager/hyprland/tests/workspace-navigation_test.lua GENERATED_HYPRLAND_LUA`.
`node home_manager/hyprland/tests/workspace-hotplug_test.mjs` exercises real
window migration on private virtual outputs; it never disconnects a real screen.
`node desktop/tests/workspaces_test.mjs` verifies the bar through isolated IPC.

Building does not activate NixOS or restart Quickshell. To apply the current
Home Manager configuration deliberately (including its other pending changes):

```sh
activation=$(nix build --print-out-paths --no-link \
  '.#nixosConfigurations.nixos.config.home-manager.users.ian.home.activationPackage' \
  | tail -1)
"$activation/activate"
systemctl --user restart quickshell.service
hyprctl reload
```

For diagnostics:

```sh
systemctl --user is-active quickshell.service
qs log -c top-bar --no-color
hyprctl -j monitors | jq 'map({name,reserved})'
hyprctl getoption general:col.active_border -j
```

The reserved area must stay stable through animations and the normal active
window border must return after closing an overlay. IPC methods live in
[shell/ShellIntegration.qml](shell/ShellIntegration.qml), for example
`qs --config top-bar ipc call topbar toggleWifi`. Some methods perform real
actions: use the fixtures for update/cleanup tests.

## Shared icons

UI icons use the complete, bundled Lucide SVG catalogue. Any feature can import
`ui/` and use the same component; names follow the Lucide catalogue:

```qml
import "../../ui"
import "../../ui/Theme.js" as Theme

Icon {
  name: "wifi"
  size: 18
  color: Theme.sideNetwork
  strokeWidth: 2
}
```

Use `spinning: true` with `name: "loader-circle"` for loading indicators.
`BarCell`, `BarDial`, `Pill` and `BeeperButton` accept `iconName` separately from
their text. Put accessible labels on the owning control. Workspace Pac-Man,
ghosts and empty dots intentionally keep their Nerd Font glyphs. Keep application logos,
avatars, user emojis and keyboard notation as their original content.

Assets are local and shared by all views, including chat. The SVG renderer
handles color/opacity and HiDPI sizing without icon fonts or per-icon effects.
The pinned version, integrity check and generator are in
[update-lucide.mjs](ui/icons/update-lucide.mjs); regeneration requires Node and
`tar`, but normal builds and runtime require no downloads. The upstream license
is bundled with the catalogue.

## Storage

Cmd+Y or a click on the storage capsule opens the on-demand disk report.
The fixed system service and shortcut require a NixOS rebuild; the preview
cannot install them. The panel offers no deletion action. Its chart is an
estimate, especially on Btrfs; physical free space is reported separately.
See the [storage constraints](docs/DESIGN_GUIDE.md#stockage) and
[collector documentation](../tools/quickshell/system-stats/README.md#on-demand-storage-breakdown).

## Messages

Beeper Desktop must remain running as the local API provider. Create an access
token in its integration settings and enter it in the connection screen; the
helper stores it in GNOME Keyring, never Nix. Disable Desktop's notification
alerts and sounds without muting every conversation, because our backend owns
notification delivery. Configure minimized startup/quit behavior using the
[Beeper service guide](../home_manager/beeper/README.md).

Drafts, staged attachments and pending-send recovery live in
`~/.local/state/quickshell-beeper`. The
[backend README](../tools/quickshell/beeper/README.md) owns credential, protocol,
media and persistence details. The
[messenger constraints](docs/DESIGN_GUIDE.md#messagerie) explain read state,
asynchronous responses, focus and rendering decisions.

The in-app `?` help is the shortcut reference. `Ctrl+H/L` moves between panes;
`Ctrl+F` in the composer folds the chat back into the bar, then opens Yazi in its usual floating
1000 × 600 Ghostty window. Selecting files, cancelling or closing Yazi restores
the chat and draft. Files are previewed individually and sent in selection order,
with the text on the first message; a failure preserves only the remaining files.
The picker preserves the original conversation if selection changes while it is
open. `BEEPER_PREVIEW_MEDIA=1` adds fictional audio to the preview, without a
real recording or account.

## Plan limits

The bar shows three logo dials: GPT/Codex's main quota, Claude's five-hour quota
and its all-model weekly quota. Rings show remaining allowance; hover for the exact
percentage. The dials are hover-only and keep the normal pointer. Reset times
and freshness remain in the accessible label. Top-right badges show available
reset credits once per provider, only when greater than zero; unknown counts stay hidden.
Press Cmd+R to refresh. One shared
controller reads the signed-in official CLIs at startup and every five minutes;
it neither reads credential files nor submits prompts or consumes reset credits.
The experimental protocol handling and failure policy are documented under
[usage limits](docs/DESIGN_GUIDE.md#limites-dutilisation).

## HHKB shortcut sheet

The held overlay uses Hyprland custom events rather than taking keyboard focus.
[KeyboardLayout.js](features/keyboard/KeyboardLayout.js) and
[KeyboardShortcuts.js](features/keyboard/KeyboardShortcuts.js) are the references
for labels; keep them aligned with
[Hyprland bindings](../home_manager/hyprland/bindings.nix) and the configured XKB
layout. See the [input constraints](docs/DESIGN_GUIDE.md#clavier-et-saisie)
for release ordering and Lafayette's dead keys.

Run the keyboard-specific checks from the repository root, with generated
keymap/Lua paths supplied explicitly:

```sh
node desktop/tests/keyboard-symbols_test.mjs KEYMAP PYTHON LIBXKBCOMMON
lua desktop/tests/keyboard-cheatsheet_test.lua GENERATED_HYPRLAND_LUA
```

The Qt view checks are included in the desktop runner; these additional checks
validate the actual XKB behavior and generated bindings without injecting
keystrokes into the desktop.
