# Code Context

## Files Retrieved
1. `home_manager/shared/additional_packages.nix` (lines 24-36, 68-76) - both `google-chrome` and `chromium` are installed through Home Manager; Google Chrome is the running browser.
2. `home_manager/hyprland/hyprland.nix` (lines 20-29, 155-182, 269-272) - browser command, Quickshell IPC keybindings, and the current Vicinae tab-launch shortcut.
3. `home_manager/hyprland/vicinae.nix` (lines 1-18, 73-88) - existing extension/native-messaging deployment proves the required Chrome integration mechanism works on this NixOS setup.
4. `home_manager/hyprland/quickshell.nix` (lines 1-30) - packages the QML tree, imports helper packages, selects `top-bar`, and starts Quickshell as a user systemd service.
5. `home_manager/hyprland/quickshell/helpers/default.nix` (lines 1-75) - established pattern for packaging shell/Python helpers and placing them in `home.packages`.
6. `home_manager/hyprland/quickshell/top-bar/shell.qml` (lines 1-15) - one shared `StatusData` instance feeds a `Bar` per screen.
7. `home_manager/hyprland/quickshell/top-bar/StatusData.qml` (lines 1-80, 344-371, 444-553, 1081-1110, 1194-1267, 1301-1369) - shared launcher state, filtering/action conventions, long-lived and one-shot `Process` patterns, JSON parsing, and `IpcHandler` entry points.
8. `home_manager/hyprland/quickshell/top-bar/Bar.qml` (lines 32-42, 187-220, 449-461) - center-overlay mode selection and where a tabs selector would be mounted.
9. `home_manager/hyprland/quickshell/top-bar/components/AppLauncher.qml` (lines 1-23, 36-48, 76-121, 171-190) - reusable interaction design (not Vicinae code): search focus, keyboard selection, list model, Enter/Escape handling.
10. `$HOME/.config/google-chrome/Default/Extensions/kcmipingpfbohfjckomimmahknoddnke/1.0.0_0/manifest.json` (local runtime file) - installed Vicinae Integration MV3 extension declares `nativeMessaging` and `tabs`, with a service worker.
11. `$HOME/.config/google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json` (local runtime symlink) - deployed Home Manager native-host manifest; equivalent Chromium symlink also exists.

## Key Code

### Browser and startup

- `home_manager/shared/additional_packages.nix:32` installs `google-chrome`; line 73 also installs `chromium`.
- `home_manager/hyprland/hyprland.nix:22` sets `$browser = "google-chrome-stable"`; line 181 binds Super+G to it. Chrome is not autostarted in the repo (`exec-once` at lines 31-35 contains only session/X setup); it is launched on demand.
- Runtime inspection returned **Google Chrome 150.0.7871.124** and **Chromium 150.0.7871.124**. The active parent process is Nix store package `google-chrome-150.0.7871.124`, using the normal `$HOME/.config/google-chrome` default data directory and Wayland. Its top-level command had no remote-debugging flag.

### Existing native messaging capability

`home_manager/hyprland/vicinae.nix:77-87` already generates manifests in both supported per-user locations:

```nix
nativeMessagingHost.text = builtins.toJSON {
  name = "com.vicinae.vicinae";
  path = "${config.programs.vicinae.package}/libexec/vicinae/vicinae-browser-link";
  type = "stdio";
  allowed_origins = [ "chrome-extension://kcmipingpfbohfjckomimmahknoddnke/" ];
};
```

Runtime evidence:
- Both manifest paths are Home Manager symlinks into `home-manager-files`.
- Extension `kcm...` version 1.0.0 is installed in Chrome Default; its manifest is MV3 with `tabs` and `nativeMessaging` permissions and a service worker.
- A live `vicinae-browser-link chrome-extension://kcm.../` process confirms Chrome successfully launches a native host.
- No files were found under `/etc/opt/chrome/policies` or `/etc/chromium/policies`; therefore extension *force-install/managed policy is not currently evidenced*. The extension appears present in profile state, while only its native host manifest is declaratively managed.

### Quickshell data/process/IPC patterns

- `quickshell.nix:2-10` copies the whole `top-bar` source tree into a store config; new QML/JS assets beneath that tree are included automatically. `quickshell.nix:12` imports helper packaging.
- `helpers/default.nix:19-75` uses `writeShellApplication`, explicit `runtimeInputs`, and `home.packages`; this is the natural place for a Chrome bridge CLI/daemon package.
- `StatusData.qml:1081-1110` shows a continuously running helper emitting newline-delimited JSON to `SplitParser`; `1194-1267` shows one-shot processes with `StdioCollector`.
- `StatusData.qml:1301-1369` exposes `target: "topbar"` functions, invoked by `qs --config top-bar ipc call topbar ...` in `hyprland.nix:155-178`.
- `shell.qml:3-14` centralizes state once, so tab results should live in `StatusData`, not per-monitor `Bar` instances.
- Existing launcher behavior can be mirrored: state and filtering in `StatusData.qml`, view in a new component, mounted alongside `AppLauncher` in `Bar.qml`, and a dedicated IPC toggle called directly from the keybind.

## Architecture

### Practical Vicinae-free integration

Recommended local design:

1. **Independent Chrome extension** (new source directory, e.g. `home_manager/hyprland/chrome-tabs-extension/`): MV3 service worker with only `tabs` and `nativeMessaging`. It handles `listTabs` with `chrome.tabs.query({})`; activation uses `chrome.tabs.update(tabId, {active:true})` followed by `chrome.windows.update(windowId, {focused:true})`. Do not copy or call the installed Vicinae extension.
2. **Independent native host/bridge** (new helper source plus package in `quickshell/helpers/default.nix`): implement Chrome's length-prefixed stdin/stdout protocol and expose a user-only Unix socket or tightly permissioned runtime file API to a small `quickshell-chrome-tabs` CLI. The extension should open/reconnect a native port so the bridge is available while Chrome runs. Use request IDs and bounded timeouts.
3. **Declarative manifest** (prefer a new dedicated HM module rather than `vicinae.nix`): install `~/.config/google-chrome/NativeMessagingHosts/<new-name>.json` (and optionally Chromium) with only the new extension origin. Extension installation itself remains an explicit deployment question: current repo proves native-host management, not managed extension force-install. A stable extension ID requires a fixed manifest `key`/packaging strategy or Chrome policy/Web Store distribution.
4. **Quickshell state** in `StatusData.qml`: add visibility/target/query/selection/results/loading/error properties; use a `Process` plus `StdioCollector` for one-shot list/activate CLI calls, or a persistent `SplitParser` process if live tab updates are desired. Parse JSON defensively as existing telemetry does.
5. **Quickshell view**: add `components/ChromeTabsLauncher.qml`, modeled on the repository's own `AppLauncher.qml` keyboard/search/list conventions; add a `tabs` center mode in `Bar.qml`. This reuses local Quickshell UI conventions, not any Vicinae component.
6. **IPC/keybinding**: expose `toggleChromeTabs()` in the existing `IpcHandler`; replace `hyprland.nix:178` with `${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar toggleChromeTabs`. Keep Super+G browser launch unchanged.
7. **Focus behavior**: after extension activation, optionally use Hyprland only as a fallback to focus the Chrome toplevel. The extension APIs should select the exact Chrome window/tab; Quickshell's existing Hyprland toplevel logic demonstrates compositor focus handling (`StatusData.qml:444-461`).

### Why not direct debugging/session parsing

The active Chrome command has no debugging endpoint, so there is no existing CDP integration to consume. Adding debugging flags alters startup/security and modern Chrome restricts default-profile remote debugging. Reading `Preferences`, `Local State`, or session files would be stale/racy and cannot reliably activate a live tab. The already proven tabs API + native messaging path is the least invasive direct architecture.

## Review Findings

- **high:** `home_manager/hyprland/hyprland.nix:178` is the sole current tabs shortcut and hard-depends on `vicinae deeplink`; it must be replaced for a genuinely Vicinae-free path.
- **high:** `home_manager/hyprland/vicinae.nix:73-88` is Vicinae-specific and must not be reused as the host implementation. Its *Home Manager manifest pattern* is useful evidence only; create a separately named host, executable, origin, and module.
- **medium:** No Chrome managed-extension policy is currently configured. A native manifest alone does not install/authorize a new extension; stable-ID installation/deployment must be solved.
- **medium:** MV3 service workers suspend. The bridge/extension protocol must reconnect and handle Chrome-not-running, host-not-found, stale tab IDs, and timeouts without hanging the Quickshell UI.
- **medium:** Current worktree already contains staged/unstaged Quickshell changes. Future implementation must preserve and integrate with those edits rather than assuming repository HEAD layout.
- **low:** Both Chrome and Chromium are installed, but the configured/running browser is Google Chrome. Supporting both manifests is easy, while multi-profile/multi-browser routing needs explicit scope.

## Residual Risks

- Local Chrome version/profile/process evidence is a point-in-time observation and may change after a flake update.
- Chrome extension installation method and stable extension ID are undecided; unpacked developer-mode installation is less declarative, while force-install policy generally needs an update source/package strategy.
- Native messaging is extension-initiated; Quickshell cannot simply invoke the native host and expect Chrome tabs. The design needs the extension-to-host connection plus a separate local IPC surface.
- Exact window focus behavior under Wayland should be tested across normal Chrome windows and installed Chrome apps.
- Tab favicons may be remote/data URLs; avoid unrestricted network fetching in QML unless explicitly designed and sanitized.

## Start Here

Open `home_manager/hyprland/quickshell/top-bar/StatusData.qml` first. It owns all shared overlay state, process parsing, actions, and IPC. Then inspect `Bar.qml:187-220,449-461` and `components/AppLauncher.qml` to add the tabs mode/view consistently, while designing the independent native bridge in `quickshell/helpers/default.nix`.

```acceptance-report
{
  "criteriaSatisfied": [
    {
      "id": "criterion-1",
      "status": "satisfied",
      "evidence": "Concrete review findings and residual risks cite repo paths/line ranges; runtime inspection identifies Chrome 150.0.7871.124, installed extension permissions, native host symlinks, process state, and absent policy files."
    }
  ],
  "changedFiles": [],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {
      "command": "google-chrome --version; chromium --version; pgrep -af chrome; inspect Chrome config/native manifests/policies",
      "result": "passed",
      "summary": "Found Chrome and Chromium 150.0.7871.124, active Google Chrome/default profile, installed Vicinae extension/native host, and no managed policy files."
    },
    {
      "command": "jq selected fields from installed extension manifest; ls native-host symlinks; inspect desktop launchers/process flags",
      "result": "passed",
      "summary": "Confirmed MV3 tabs/nativeMessaging permissions, HM-managed host symlinks, and no remote-debugging startup flag."
    },
    {
      "command": "git status --short and targeted numbered source reads",
      "result": "passed",
      "summary": "Confirmed pre-existing staged/unstaged Quickshell changes and gathered exact source line evidence."
    }
  ],
  "validationOutput": [
    "Google Chrome 150.0.7871.124; Chromium 150.0.7871.124.",
    "Installed integration extension manifest: MV3, permissions [nativeMessaging, tabs], service_worker background.js.",
    "No /etc Chrome/Chromium policy files found; active Chrome parent has no remote-debugging flag."
  ],
  "residualRisks": [
    "Stable extension ID and declarative installation/update mechanism remain to be selected.",
    "MV3 suspension/reconnection and Wayland window-focus behavior require implementation testing.",
    "Working tree already has unrelated staged and unstaged Quickshell edits."
  ],
  "noStagedFiles": false,
  "diffSummary": "No implementation files edited; only this requested scouting artifact was written.",
  "reviewFindings": [
    "high: home_manager/hyprland/hyprland.nix:178 - current Chrome-tabs shortcut is hardwired to a Vicinae deeplink.",
    "high: home_manager/hyprland/vicinae.nix:73-88 - existing host is Vicinae-specific; a new implementation must use an independent extension, host name, executable, and origin.",
    "medium: Chrome policy directories - no managed extension installation policy was found, so a new extension deployment mechanism is still required.",
    "medium: native messaging lifecycle - Chrome extensions initiate native hosts; a separate authenticated/user-only local IPC bridge is required for Quickshell."
  ],
  "manualNotes": "Runtime inspection was read-only. The output artifact is the only file written by this scout."
}
```
