# Quickshell layout

- `top-bar/` — active Quickshell configuration managed by Home Manager.
  - `shell.qml`, `Bar.qml`, `StatusData.qml` — shell entry point, panel and shared state.
  - `components/` — visual components used by `Bar.qml`.
  - `scripts/system-stats.py` — persistent CPU, memory, disk and brightness telemetry source.
  - `docs/DESIGN_GUIDE.md` — visual and animation conventions for future changes.
- `helpers/` — Nix-packaged commands used by the active shell.
  - `quickshell-update-checker`
  - `quickshell-update-installer`
  - `quickshell-gpu-monitor`
  - `quickshell-weather`

The old helper definitions remain in `../waybar.nix` for compatibility, but are only installed when Waybar is enabled. Waybar itself remains disabled.
