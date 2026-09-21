# Quickshell layout

- `top-bar/` — active Quickshell configuration managed by Home Manager.
  - `shell.qml`, `Bar.qml`, `StatusData.qml` — shell entry point, panel and shared state.
  - `components/` — visual components used by `Bar.qml`.
  - `docs/DESIGN_GUIDE.md` — visual and animation conventions for future changes.
- `../../tools/README.md` — source layout, with one directory per logical tool.
- `../../packages/default.nix` — helper packages exported through `localPackages`, with one Nix recipe per tool.
  - `quickshell-update-checker`
  - `quickshell-update-installer`
  - `quickshell-system-stats`
  - `quickshell-gpu-monitor`
  - `quickshell-weather`
  - `quickshell-speedtest`

`../../tools/quickshell/chrome-tabs/` contains the Rust TabCtl adapter and favicon
cache, packaged by `../../packages/quickshell/chrome-tabs.nix`. `../tabctl.nix`
installs it with TabCtl and registers the Chrome native messaging host.

## HHKB shortcut sheet

Hold Cmd+' (apostrophe) to display the Catppuccin Macchiato keyboard on the
focused monitor. Releasing apostrophe or either Cmd key hides it. Cmd+P opens
Chrome tabs. The sheet does not take keyboard focus or intercept pointer input.
While holding Cmd+apostrophe, press Tab to cycle **Clavier → Navigateur → Vim**,
or Shift+Tab to go backwards. Each opening starts on Clavier. Tab is consumed
by Hyprland while the sheet is shown, so it does not start voice dictation or
reach the application; Cmd+Tab keeps its usual dictation behavior when hidden.
The overlay covers the focused monitor with an 82% black scrim. The keyboard
panel is transparent, with opaque keycaps and labels; both
the keyboard and scrim disappear together on release.

`top-bar/KeyboardCheatsheet.qml` receives ordered Hyprland custom events from
`../hyprland/bindings.nix`; release bindings also work across submaps and modifier
changes. Reloading the compositor config or changing submaps closes the sheet.
`top-bar/components/KeyboardSheet.qml` renders the diagram, while
`KeyboardLayout.js` contains its HHKB geometry and the configured Cmd actions.
`KeyboardShortcuts.js` supplies the browser and Vim reference labels on the same
physical keyboard, plus cards for sequences and modifier combinations. The
browser page includes the custom Surfingkeys J/K bindings; the Vim page covers
Surfingkeys' built-in input editor, including its `:wq` and `:q` behavior.
Keep these labels in sync when changing shortcuts. Firmware-specific Fn mappings
are not assumed.

The diagram shows Lafayette 0.9's six character levels: base at bottom left,
Shift at top left, AltGr at bottom right, Shift+AltGr at top right,
★ then key at bottom centre and ★ then Shift+key at top centre.
Uppercase letters, including accented capitals, are omitted from the diagram.
Dotted circles mark dead accents. The ★ key is a one-shot level latch: tap
and release it before typing w for é, e for è, a for à, c for ç, or d for ê.
Double ★ followed by e gives ë. Semicolon is Shift+comma; colon is Shift+period.
The separate Compose key remains on Caps Lock; AltGr is for programming symbols.

`../hyprland/lafayette.nix` fetches the official 0.9 symbols with a fixed hash
and compiles a standalone XKB keymap for Hyprland's `input.kb_file`. No firmware
changes, system XKB overwrites or custom Compose table are needed.
To restore the previous layout, remove `kb_file` from `settings.nix`, set
`kb_layout = "fr"`, `kb_variant = "us"`, keep `compose:caps`, and update the
diagram. The Cmd+apostrophe sheet shortcut works with either layout and avoids
arming Lafayette's one-shot accent latch when opening the sheet.

Run `node top-bar/tests/keyboard-symbols_test.mjs KEYMAP [PYTHON] [LIBXKBCOMMON]`
to check the diagram and actual released-latch, uppercase, AltGr and tréma behavior
without injecting any keystrokes into the desktop.
The key above Return is Backspace; the key next to right Shift is Delete, and
the small bottom-right key is Fn, following the user's keyboard mapping.
The key immediately right of Space is AltGr; the left Cmd key is used for shortcuts.

`tests/tst_KeyboardSheet.qml` checks page cycling, context-specific shortcuts,
label bounds and opaque keycaps with `qmltestrunner` offscreen.
`tests/keyboard-cheatsheet_test.lua GENERATED_HYPRLAND_LUA` exercises the generated
bindings, including Tab without dictation, release ordering, and cleanup after
reloads or submap changes. It does not inject events into the desktop.
