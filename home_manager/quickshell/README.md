# Quickshell layout

- `top-bar/` — active Quickshell configuration managed by Home Manager.
  - `shell.qml`, `Bar.qml`, `StatusData.qml` — shell entry point, panel and shared state.
  - `components/` — visual components used by `Bar.qml`.
  - `docs/DESIGN_GUIDE.md` — visual and animation conventions for future changes.
- `../../tools/quickshell/` — helper sources and tests, including persistent system telemetry.
- `../../packages/quickshell.nix` — helper packages exported through `localPackages`.
  - `quickshell-update-checker`
  - `quickshell-update-installer`
  - `quickshell-system-stats`
  - `quickshell-gpu-monitor`
  - `quickshell-weather`
  - `quickshell-speedtest`

The Chrome favicon helper remains in `helpers/chrome-tab-favicons.py` and is
packaged by `../tabctl.nix` with the Chrome-specific commands.
