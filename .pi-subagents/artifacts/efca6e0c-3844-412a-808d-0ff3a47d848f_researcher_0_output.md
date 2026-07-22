# Research: Direct Chrome tab enumeration and activation from a Linux/Quickshell launcher

## Summary

The best supported design is a small Manifest V3 Chrome extension using `chrome.tabs`, connected to a tightly scoped native-messaging broker that exposes a user-only Unix socket to Quickshell. It works with the user's normal running profile, provides live titles/URLs and stable-in-session tab/window IDs, and can both select the tab and focus its Chrome window.

CDP is simpler only when it is acceptable to run Chrome under a dedicated non-default user-data directory with remote debugging enabled. Since Chrome 136, the ordinary default data directory deliberately ignores `--remote-debugging-port` and `--remote-debugging-pipe`; file parsing, AT-SPI, and desktop window APIs are inferior fallbacks rather than complete supported tab-control APIs.

## Recommendation

### Preferred architecture: MV3 extension + native-messaging broker

1. Install an extension with only `"tabs"` and `"nativeMessaging"` permissions. Its service worker calls `chrome.tabs.query({})` and returns `{id, windowId, index, title, url, favIconUrl, active, incognito}`.
2. To activate a result, call `chrome.tabs.update(tabId, {active: true})`, then `chrome.windows.update(windowId, {focused: true})`. Chrome documents that making a tab active does **not** itself focus its window.
3. The extension opens `runtime.connectNative("…")`. Chrome starts the registered native host and communicates over length-prefixed JSON on stdin/stdout. The host/broker multiplexes that channel with a Unix socket such as `$XDG_RUNTIME_DIR/chrome-tabs.sock`; Quickshell talks only to that socket.
4. Create the socket with mode `0600`, reject peers of a different UID, validate a small command schema, and never accept arbitrary JavaScript/CDP operations. Pin `allowed_origins` to the exact extension ID and use a stable extension signing key/ID.
5. Cache tab state in the extension/broker and subscribe to `tabs.onCreated`, `onUpdated`, `onRemoved`, `onMoved`, and `onActivated`, or query on each launcher invocation. A native-messaging connection keeps an extension service worker alive in Chrome 105+, but reconnect after host/port failure.

On Linux, the per-user native host manifest belongs at:

- Google Chrome: `~/.config/google-chrome/NativeMessagingHosts/<host-name>.json`
- Chromium: `~/.config/chromium/NativeMessagingHosts/<host-name>.json`

The manifest's executable `path` must be absolute. For NixOS, declaratively install the extension, executable, manifest, and a user service/socket if the broker is separate. Each Chrome profile needs the extension installed; incognito requires the user's explicit “Allow in Incognito” choice and careful handling of split/spanning extension mode.

## Findings

1. **Official extension API is the only narrow, live, normal-profile tab API (recommended).** `tabs.query({})` returns all tabs; the `tabs` permission reveals the sensitive `url`, `pendingUrl`, `title`, and `favIconUrl` fields. `activeTab` is insufficient for launcher-wide enumeration because it grants temporary access only to a user-invoked current tab. Tab IDs last only for the current browser session. Activation requires both `tabs.update(..., {active:true})` and, for another window, `windows.update(..., {focused:true})`. [Chrome tabs API](https://developer.chrome.com/docs/extensions/reference/api/tabs) [Chrome windows API](https://developer.chrome.com/docs/extensions/reference/api/windows)

2. **Native messaging is supported but extension-initiated, so a broker is required.** Chrome launches an allowed host as a separate process and provides only stdin/stdout; `connectNative()` keeps it alive while the port exists, whereas `sendNativeMessage()` starts one process per request. The host manifest restricts callers with non-wildcard `allowed_origins`. A launcher cannot independently attach to Chrome's private native-messaging pipes, hence the host must expose a separate local IPC endpoint or coordinate with a daemon. [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) [Service-worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)

3. **Extension permission/deployment cost is explicit but bounded.** Chrome displays “Read your browsing history” for `tabs` and “Communicate with cooperating native applications” for `nativeMessaging`. The extension sees tab metadata but needs no host permissions or content-script injection for this use case. Compromise of the extension or native broker exposes the user's open-tab metadata and activation ability, so avoid `<all_urls>`, `scripting`, and remotely hosted code. [Permissions list](https://developer.chrome.com/docs/extensions/reference/permissions-list)

4. **CDP provides trivial enumeration/activation when Chrome was started for debugging.** The HTTP discovery endpoint `GET /json/list` yields page targets including IDs, titles, URLs, and WebSocket debugger URLs; `GET /json/activate/{targetId}` brings a page forward. Equivalently, the browser WebSocket supports `Target.getTargets` and `Target.activateTarget`. Tip-of-tree CDP has no compatibility guarantee, but these target methods and HTTP endpoints are longstanding. [CDP HTTP endpoints](https://chromedevtools.github.io/devtools-protocol/) [CDP Target domain](https://chromedevtools.github.io/devtools-protocol/tot/Target/)

5. **High — Chrome 136+ blocks the obvious CDP setup for the everyday default profile.** Since Chrome 136 (stable April 2025), `--remote-debugging-port` and `--remote-debugging-pipe` are ignored when they target the default Chrome data directory. Chrome requires `--user-data-dir=<non-standard-directory>` and recommends a separate profile or Chrome for Testing. Thus CDP cannot simply be added to an already-running normal-profile Chrome; adopting it changes how Chrome is launched and where the user's profile lives. [Chrome security announcement](https://developer.chrome.com/blog/remote-debugging-port) [Chrome user-data directories](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)

6. **High — CDP grants far more privilege than tab switching.** A debugging client can inspect page content, execute JavaScript, access storage/cookies through protocol domains, and navigate/close targets. The discovery/WebSocket service has no launcher-specific authorization in the documented endpoint protocol. Keep it local and never expose it to an untrusted network or other users. A custom profile reduces damage but does not narrow CDP privileges. This makes CDP a good opt-in power-user mode, not the default integration.

7. **Chrome 144+ adds a consented existing-session bridge, but it is documented for Chrome DevTools MCP/agents, not as a general desktop tab API.** Users enable Remote Debugging at `chrome://inspect/#remote-debugging`; an auto-connect attempt then shows an Allow dialog. This can reach a personal running browser without the old startup-port workflow, but the official configuration is tied to `chrome-devtools-mcp --autoConnect`, has broad debugger power and interactive consent, and is excessive for a launcher. Do not assume a stable generic IPC contract for arbitrary Quickshell clients. [Chrome 144+ auto-connect](https://developer.chrome.com/docs/devtools/agents/get-started/configuration) [Auto-connect use case](https://developer.chrome.com/docs/devtools/agents/use-cases/auto-connect)

8. **High — profile/session-file parsing is an unsupported, stale snapshot and cannot reliably activate a live tab.** Chrome's own `SessionService` says commands are only *periodically* flushed and files are rebuilt occasionally for later restoration. Current Chromium source stores timestamped binary command streams under `<profile>/Sessions/` or `<profile>/EncryptedSessions/`; current source supports a version-3 cleartext format and a version-5 OSCrypt-encrypted format. The reader explicitly tolerates incomplete trailing writes. The serialized `SessionID` is an internal restoration identifier, not a documented live `chrome.tabs`/CDP target ID, so parsing may recover titles/URLs but offers no supported activation path. [SessionService](https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/browser/sessions/session_service.h) [Command storage backend](https://chromium.googlesource.com/chromium/src/+/main/components/sessions/core/command_storage_backend.cc)

9. **Medium — AT-SPI can be a title-only, best-effort fallback, not a stable Chrome integration.** Chromium maps browser UI accessibility roles to Linux AT-SPI/ATK, including “page tab” and “page tab list”. AT-SPI exposes roles/names and an Action interface whose actions can be invoked, so a client can walk Chrome's accessibility tree, find tab objects, and attempt their select/click action. However, hierarchy, accessible names, virtualization/hidden tabs, action names, accessibility enablement, and behavior can change; URLs are not guaranteed in tab-strip objects; and focusing the correct top-level window remains separate. Chromium also notes accessibility may be inactive until assistive technology connects because it has performance cost. [Chromium accessibility overview](https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/overview.md) [Chromium Linux role mapping](https://chromium.googlesource.com/chromium/src/+/main/ui/accessibility/platform/ax_platform_node_auralinux.cc) [AT-SPI roles](https://docs.gtk.org/atspi2/enum.Role.html) [AT-SPI Action](https://docs.gtk.org/atspi2/iface.Action.html)

10. **No documented desktop D-Bus/MPRIS/tab interface exists in desktop Chrome.** Chrome's Linux integration consumes freedesktop services (for example portals/file-manager operations), but its documented/official code does not export a tab-control service. Third-party projects claiming Chrome tabs over D-Bus add their own extension/bridge, confirming that D-Bus is transport supplied by that project rather than Chrome. X11 EWMH `_NET_ACTIVE_WINDOW` and compositor/Quickshell window APIs can focus a Chrome *top-level window* but expose neither its tab list nor an in-window tab selector; Wayland makes cross-client activation compositor-specific. [Chromium Linux platform integration](https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/platform_util_linux.cc) [EWMH active-window specification](https://specifications.freedesktop.org/wm/latest/ar01s03.html)

## Comparison

| Method | Normal running profile | Live title/URL | Activate tab/window | Deployment | Security / reliability |
|---|---|---:|---:|---|---|
| Extension + native messaging | Yes | Yes | Yes / Yes | Extension, host manifest, broker socket | **Best balance**; explicit permissions, narrow commands |
| CDP remote-debugging port | No by default on Chrome 136+; yes with non-standard data dir | Yes | Yes / generally target foreground | Launch flags and dedicated profile | **High privilege**; simple protocol, profile disruption |
| Chrome 144+ MCP auto-connect | Yes, after enablement/consent | Yes via debugger tooling | Possible | Node/MCP tooling and user approval | High privilege, overbuilt, not generic launcher API |
| Session-file parsing | Reads profile snapshot | Sometimes/stale; may be encrypted | No supported mapping | Version-specific parser, profile discovery | **Brittle/unsupported**, race and format churn |
| AT-SPI | Usually, if accessibility tree available | Title likely; URL not guaranteed | Best-effort action; separate window focus | AT-SPI client/accessibility setup | UI-tree-dependent and privacy-sensitive |
| X11/Wayland window APIs | Yes | Only top-level window title | Window only | WM/compositor-specific | Cannot enumerate/select tabs |
| Chrome desktop D-Bus/MPRIS | No documented interface | No | No | N/A | Third-party bridges still require an extension/automation layer |

## Security and deployment tradeoffs

- **Metadata sensitivity:** open-tab titles and URLs disclose browsing activity. Keep results in memory, do not log by default, and redact internal URLs if unnecessary.
- **IPC boundary:** put the Unix socket in `$XDG_RUNTIME_DIR`, mode `0600`; validate peer UID and message sizes. Native messaging itself caps host-to-Chrome messages at 1 MiB and Chrome-to-host messages at 64 MiB.
- **Extension boundary:** fixed `allowed_origins`, stable extension ID, minimal permissions, no content scripts. An unpacked developer-mode extension is easiest locally but produces management/developer-mode friction; policy or Web Store deployment is cleaner for multiple machines.
- **Profiles/incognito:** install/enable per profile. Do not merge regular and incognito results without a visible marker. Native-host manifests are browser/user-data-dir scoped, and multiple extension contexts may create multiple host processes.
- **CDP boundary:** use only a dedicated non-default `--user-data-dir`, local-only endpoint, and a random/ephemeral port where practical. Treat any process that can connect as able to take over browsing data in that debug profile.
- **Accessibility boundary:** AT-SPI consumers can observe more UI than just Chrome tabs. It is less deployment work but is not least privilege in practice and is sensitive to Chrome UI changes.

## Concrete review findings

- **high:** `<Chrome user-data-dir>/Default/Sessions/` or `<profile>/EncryptedSessions/` — do not implement the primary launcher by parsing these files; writes are periodic, binary formats are internal/versioned, 2026-era source supports OSCrypt-encrypted sessions, and records cannot be mapped through a supported API to live tabs.
- **high:** Chrome launch configuration — do not add a remote-debugging port to the everyday profile as the primary solution; Chrome 136+ ignores it for the default data directory, while moving daily browsing to a debuggable custom directory restores a broad takeover surface.
- **medium:** `~/.config/google-chrome/NativeMessagingHosts/<host>.json` — ensure `allowed_origins` contains only the pinned extension origin and `path` is an immutable absolute Nix-store or otherwise root/user-controlled executable.
- **medium:** `$XDG_RUNTIME_DIR/chrome-tabs.sock` — require `0600`, same-UID peer checks, bounded JSON frames, and a narrow allowlist (`list`, `activate`); otherwise another local process could exfiltrate tab metadata or cause focus changes.
- **low:** extension service worker — reconnect the native port after crashes/restarts and re-query tabs after reconnect; IDs are browser-session-local and cached state can become stale.

## Sources

### Kept

- [chrome.tabs API](https://developer.chrome.com/docs/extensions/reference/api/tabs) — primary API contract for enumeration, metadata permissions, IDs, events, and activation.
- [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) — primary transport, registration paths, origin allowlist, and framing contract.
- [Remote-debugging switch changes](https://developer.chrome.com/blog/remote-debugging-port) — authoritative Chrome 136 security behavior.
- [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/) and [Target domain](https://chromedevtools.github.io/devtools-protocol/tot/Target/) — authoritative discovery and activation operations.
- [SessionService](https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/browser/sessions/session_service.h) and [command storage](https://chromium.googlesource.com/chromium/src/+/main/components/sessions/core/command_storage_backend.cc) — direct current implementation evidence for periodic persistence, versioning, and encryption.
- [Chromium accessibility overview](https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/overview.md) and [AT-SPI docs](https://docs.gtk.org/atspi2/iface.Action.html) — primary implementation/platform evidence.
- [Chrome 144+ existing-session configuration](https://developer.chrome.com/docs/devtools/agents/get-started/configuration) — current 2026 behavior and its MCP-specific scope.

### Dropped

- Stack Overflow answers about querying Chrome tabs — old and superseded by Chrome 136 restrictions.
- `tabctl`, `dbus-tabs`, and Chrome-favicon D-Bus bridges — useful prototypes, but they create a custom extension/daemon interface rather than document a Chrome-supported desktop API.
- Old `Current Tabs` / `Last Tabs` parser guides — obsolete after timestamped `Sessions/` storage and current encrypted format work.
- Selenium/ChromeDriver wrappers — add no capability over CDP for this narrow task and have limitations when attaching to an existing session.

## Gaps and residual risks

- Chrome does not publish a guarantee that its Linux tab-strip accessibility hierarchy or action naming remains stable. AT-SPI behavior should be manually tested against the exact Chrome build/theme/tab-strip mode if retained as fallback.
- The Chrome 144 auto-connect documentation specifies Chrome DevTools MCP rather than a public generic-client handshake; a launcher should not depend on its internal transport without additional Chromium-source validation.
- Exact encrypted-session rollout may vary by Chrome channel/build even though current Chromium source supports it. This strengthens, rather than weakens, the recommendation not to parse files.
- Multi-profile and incognito native-host process coordination needs an explicit product choice and integration test; the API/host docs do not supply a stable human-readable profile identity in each message.