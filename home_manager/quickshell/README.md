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
