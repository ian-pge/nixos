# Desktop shell

This directory is the Quickshell application, not a collection of Home Manager
configuration fragments. It contains the bar, the messenger, shared visual
components and their local tests. It remains in the NixOS repository and uses
the same flake as the command-line tools.

## Source layout and responsibilities

```text
desktop/
  shell.qml                  # session entry point
  shell/                     # shared coordination, surfaces and messenger host
  bar/                       # bar layout and independent CentralCapsule
  ui/                        # theme, geometry and reusable visual primitives
  features/
    audio/                   # audio devices and independent MPRIS controller
    auth/                    # generic Polkit agent and transient credential input
    brightness/              # monitor targeting, batched changes and verified values
    calendar/                # calendar, weather state and views
    dictation/               # Voxtype state and waveform bridge
    keyboard/
    launchers/
    messenger/               # chat state, interface, media and design preview
    network/                 # independent network and Bluetooth controllers
    notifications/
    power/                   # laptop and peripheral battery presentation
    system/                  # collector lifetime, telemetry and process subscriptions
    updates/                 # checker/build/install/cleanup state machine and view
    workspaces/
  previews/                  # isolated visual playgrounds
  tests/                     # QML tests and integration harnesses
  docs/DESIGN_GUIDE.md        # visual decisions and regression pitfalls
```

The boundaries are intentional:

- `shell.qml` composes one instance of each domain controller and a `services`
  registry containing references only. The registry has no state-forwarding
  aliases or business logic. Views receive their specific controller.
- `shell/ShellCoordinator.qml` owns the one active bar mode and target monitor,
  presentation timeouts, authentication interruption/restoration and focus
  policy. `ShellIntegration.qml` preserves the public `topbar` IPC commands and
  manages the temporary Hyprland border indication. Neither owns device state,
  credentials, network protocols or update subprocesses.
- `bar/Bar.qml` lays out the surface and side modules. `CentralCapsule.qml` owns
  central geometry, content layers, transitions and the width cap. It supplies
  the geometry for the chat transformation, not the Beeper protocol.
- Each feature owns its state and interface. `features/messenger/BeeperData.qml`
  bridges the Go protocol; the other messenger components handle presentation,
  navigation and editing. The chat's lifetime is separate from temporary bar
  widgets, even though it visually grows out of the central capsule.
- `ui/` contains shared building blocks and `Theme.js`, not service state.
- [`../tools/`](../tools/README.md) keeps Go, Rust and script sources. In particular,
  the messenger backend remains in `tools/quickshell/beeper/`; it is not copied
  into `desktop/`.
- [`../packages/quickshell/`](../packages/quickshell/) contains Nix recipes.
  `runtime.nix` wraps Quickshell with Liquid Glass and Qt Multimedia imports;
  `desktop.nix` filters the application sources and pins helper paths to the Nix
  store. Tests and documentation are not part of the installed application.
- [`../home_manager/quickshell.nix`](../home_manager/quickshell.nix) only installs,
  configures and starts the application. No second QML source tree lives there.

Domain state and operations now have explicit owners:

| Domain | Controller |
|---|---|
| Wi-Fi/Ethernet, scans, connection and speed test | `features/network/NetworkController.qml` |
| Bluetooth discovery, pairing and connection | `features/network/BluetoothController.qml` |
| Update checks, build, confirmation, installation and cleanup | `features/updates/UpdateController.qml` |
| Generic authentication and transient password input | `features/auth/PolkitController.qml` |
| Audio devices and volume / media playback | `features/audio/AudioController.qml` / `MediaController.qml` |
| Display brightness and command batching | `features/brightness/BrightnessController.qml` |
| Calendar navigation and shared weather | `features/calendar/CalendarController.qml` / `WeatherData.qml` |
| Dictation state and audio bridge | `features/dictation/DictationController.qml` |
| Collector processes and telemetry model | `features/system/SystemController.qml` / `SystemData.qml` |
| Laptop and peripheral battery state | `features/power/PowerController.qml` |
| Application and Chrome-tab search | `features/launchers/AppLauncherController.qml` / `ChromeTabsController.qml` |
| Messenger presentation and surface | `shell/MessengerController.qml` / `MessengerHost.qml` |

The old shared state facade and its compatibility aliases are removed. Keep
new feature-specific logic in its feature; do not move it into the coordinator
or the composition registry. Presentation requests use narrow signals, while
controllers keep their processes and sensitive transient state. In particular,
closing a network selector ends its scan/password lifecycle; closing the update
view does not stop a running operation. Polkit is not an update subservice: the
shell snapshots the previous panel and monitor for an external auth request.

Folder boundaries are not process boundaries: Quickshell still owns the lifetime
of its persistent helper processes, including the Go messenger backend.

The installed configuration name remains `top-bar`, the IPC target remains
`topbar`, and the user service remains `quickshell.service`. Existing runtime
cache/state paths, including `quickshell/top-bar`, have not moved with the sources.

## Build, preview and test

Run these commands from the repository root:

```sh
# Build only; does not change the running session.
nix build --no-link .#quickshellRuntime .#quickshellDesktop .#quickshellBeeperPreview

# Fictional conversations, without Beeper or credentials.
nix run .#quickshellBeeperPreview

# Reproducible local regression runner; nothing is globally installed.
nix develop .#desktop -c node desktop/tests/run.mjs

# Alternative when test dependencies are already available in the environment:
quickshell_runtime=$(nix build --no-link --print-out-paths .#quickshellRuntime)
node desktop/tests/run.mjs "$quickshell_runtime/bin/quickshell"
```

The `desktop` development shell supplies the same wrapped runtime as Home
Manager, Node.js, D-Bus, `notify-send` and Qt's test runner. It sets
`QMLTESTRUNNER` and `BEEPER_TEST_BACKEND` to pinned executables, so the plain Qt
tests and the Go demo-protocol integration run without global installations.
It does not alter the Go, Rust or C++ development shells. The local runner is
not a Nix flake check or an automatically configured CI job.
Individual harnesses remain directly runnable. For a real Wayland component
compile, use the private nested compositor harness from an existing Wayland
session (requires Hyprland and D-Bus):

```sh
nix develop .#desktop -c node desktop/tests/messenger-wayland_test.mjs qs

# Complete object graph, with helpers/auth disabled, in the private compositor.
nix develop .#desktop -c node desktop/tests/messenger-wayland_test.mjs qs --desktop
```

Use the wrapped runtime for previews and tests, not bare `pkgs.quickshell`, so
Liquid Glass and Qt Multimedia resolve identically. Do not launch `shell.qml`
alongside the installed session merely to validate compilation: it starts real
services and helpers. The harnesses provide isolated fixtures/private sessions.
The `--desktop` fixture uses the production composition with `servicesEnabled:
false`; this disables helper processes, network selector activation and native
authentication. Its bar still instantiates the real UI/controller bindings.
Backend tests and build instructions remain in each tool's README. See the
[design guide](docs/DESIGN_GUIDE.md) for animation invariants and manual checks.

Controller tests inject native-model stand-ins, fake command transports and
authentication flows. The update/auth fixture never instantiates a native
Polkit agent or runs the real checker, installer or cleaner. It covers explicit
installation confirmation, operation exclusion, early exits, stale output,
credential clearing and keyboard routing. Shell tests exercise interruption and
restoration with fake services rather than changing the real session. Building
or running these tests does not activate NixOS or restart Quickshell.

## Messages

Cmd+D transforms the central capsule into the messenger on the active monitor,
centred in the work area below the top bar. Its height is a full-height Hyprland
window's outer frame minus 100 logical pixels: 50 px above and below, after the
bar reserve and 10 px top/bottom gaps. Width remains capped at 1280 px. The source contents fade as the
surface expands; there is no separate bubble or connecting neck. Volume and
brightness indicators and non-chat notifications still appear in the top bar without closing, moving
or resizing the chat, and all bar widgets keep their normal maximum width.
Other central panels replace the chat, and opening the chat closes them. This
includes weather, audio-device selection, network, launchers and updates. Passive
track-change feedback does not unexpectedly close a conversation.
Closing transforms the panel back into the current central capsule. Both
directions start quickly and slow near their destination (`OutCubic`, 360 ms
for a full traversal); reversing midway keeps the current geometry continuous.
When switching from chat to another widget, the widget's final dimensions are
set before closing. One glass surface owns the whole transformation, then hands
off to the capsule at the shared endpoint; no separate size animation finishes
afterward. Opening captures the previous widget before its mode changes.
Clicking outside leaves the chat open and
releases keyboard focus. Enter focuses the composer; inside it, Enter sends and
Shift+Enter adds a newline. When replying or editing, Escape first cancels that
mode while keeping typing focus and the draft. If an attachment remains, the
next Escape removes it while preserving draft text and typing focus. Once these
previews are cleared, Escape returns to the conversation list, then another
closes the panel. Outside text input, `j/k`
selects conversations on the left. `Ctrl+J/K` enters message selection at the
newest message, then selects and reveals the next/previous message. Returning to
conversations, focusing the composer, sending a reply, or leaving the chat clears
that selection, so the next entry starts at the newest message again. Draft text
is preserved. `l` also enters selection; `h` returns to conversations.
The `i` shortcut and action palette are removed.
With a message selected, `1` reacts with 😂, `2` with 💜, `3` with 🔥, `4` with 💯,
and `5` with 🤡. Telegram uses its standard equivalents 🤣 and ❤️ for `1` and `2`,
including when the sidebar shows All; the keyboard help follows the current chat.
A different digit replaces your reaction; pressing the same digit
again removes it. Other participants' reactions stay intact. Changes are sent in
order per message, including rapid key presses, and refresh that exact message
even outside the newest history page. Space plays/pauses the selected audio message or opens its photo,
GIF or video. Photos and videos fill the selected monitor as far as their aspect ratio allows,
including the top-bar area, without a title or frame. Videos keep playback
controls along the bottom; photos have no toolbar. The desktop and
messenger behind them are blurred by the `quickshell-messenger-photo` layer rule.
For photos, Space or Escape returns to the same chat and message selection.
Videos start playing on opening: Space toggles play/pause, `h/l` seek backwards
or forwards by five seconds, and Escape closes the viewer. The inline players
are paused while a video is fullscreen; closing also stops the fullscreen player,
including when a download finishes later. A paused video stays paused after seeking.
The viewer owns a
separate fullscreen layer surface, so the chat and bar keep their normal geometry.
Both surfaces stay in the focus whitelist. Closing the photo retires its old grab
before hiding the window, then creates a new grab for the chat, so a delayed
compositor event cannot discard keyboard focus after the return.
It reveals an offscreen selection before starting
playback; a second press cancels playback waiting for a download. These keys remain
ordinary characters in text fields; `?` shows the help.
Opening the panel with no selected conversation automatically selects the first
visible chat once the list is available. Network/archive filters still apply;
an existing selection or an explicit notification target takes precedence.
Opening a conversation, scrolling to its latest messages, or typing a draft
does not mark it read. Only a successfully accepted reply or the `m` shortcut
outside text input does so, on every network. Replies mark through the last
known message at send time so incoming messages arriving during the request stay
unread. Failed/uncertain sends leave the read state unchanged. Chat-banner
suppression follows whether the messenger is open, independently of keyboard
focus and the unread badge; notification sounds continue.
Outside text input and conversation search, `n` marks the current conversation
unread again. A blank yellow badge, with the same 26 px diameter as numbered badges,
represents the manual unread flag when there are no new messages to count;
`m` clears it by marking the conversation read.
Outside text input and conversation search, `u` toggles unread-first sorting;
pressing it again restores Beeper's current normal order. Manual unread reminders
are included. Each group's original order and the network/archive/search filters
are preserved, as are the open conversation, draft, message selection and read
state. The sidebar returns to the top and an arrow beside the unread counter
indicates the mode. This view preference is shared across monitors. While active,
older chat pages are fetched too, so older unread conversations rise to the top
without scrolling; closing the panel or disabling the mode stops this prefetch,
and a failed page uses the normal pagination retry guard.
The sidebar keeps an already-visible selection on screen when the API reorders
it after a read-state change. It does not return to an offscreen selection or
interrupt wheel/scrollbar navigation during background refreshes. Read-state
replies update only read fields in place, preserving title/network metadata.
The top row shows the number of unread conversations in the selected network
(`All` sums all networks), including manual unread flags and muted/low-priority
chats. A manual unread marker takes precedence over the archive filter in both
the list and counter: Beeper can return `isArchived: true` together with
`isMarkedUnread: true`. We keep that reminder visible without unarchiving the
conversation in Beeper. `a` switches from the inbox to **only archived chats**
in the current network; pressing `a` again returns to the inbox. It does not mix
ordinary inbox chats into the archive view. This view preference
is shared across monitors and follows Tab network switching. An archive badge on
the network logo indicates the mode, and archived rows have a small archive icon.
`Shift+A` archives/restores the selected conversation through the
[public archive endpoint](https://developers.beeper.com/desktop-api-reference/resources/chats/methods/archive/).
The UI waits for success, preserves drafts/unread state, and ignores stale list
responses that predate a confirmed archive. Errors keep the conversation in place.
The manual unread reminder exception above remains intentional. Escape hides
archives before closing the messenger, once out of text/message navigation.
The counter shows only archived unread conversations in the archive view,
including manually marked unread archives. It uses a dedicated count rather
than subtracting the overlapping inbox and total counts. Restoring a conversation
removes it from this view and selects the next archive, or leaves an empty view.
Explicit chat targets switch views when needed to keep the selection visible.
It counts each conversation once, not its unread
messages. The Go helper scans the full public chat catalog, independently of the
sidebar's loaded pages. Passive refreshes are coalesced and throttled to three
seconds; explicit read/unread actions trigger a fresh count. While unavailable,
the label shows a dash, never a fabricated zero or a partial total.
`Tab` cycles All → Telegram → WhatsApp → Instagram → SMS, and `Shift+Tab` reverses
that order. SMS includes Beeper's Google Messages conversations.
`/` opens conversation search beside the network logo. Tab retains its
normal editing/dialog behaviour while typing. `Ctrl+/` opens a compact text
search bar to the right of the conversation name, within the existing header.
It uses a compact counter on narrow windows, without taking height from history.
Type, then Enter to select the first
match; `n`/`N`, `j`/`k` or Ctrl+J/K move between matches outside the input.
Ctrl+/ edits the query again and Escape closes the search without closing chat.
All visible occurrences of the query words are highlighted in Macchiato Yellow,
ignoring case and accents; closing or clearing the search removes the highlights.
Original plain text still determines bubble geometry. Only escaped, locally
generated spans use [Qt's native rich-text background formatting](https://doc.qt.io/qt-6/richtext-html-subset.html),
so search styling cannot turn message text into HTML links or remote images.
Search uses the [public message search endpoint](https://developers.beeper.com/desktop-api-reference/resources/messages/methods/search/),
scoped to the current chat, including muted/low-priority conversations. Results
and older context pages load as needed using the API's opaque cursors; neither
message IDs nor sort keys are used as fabricated cursors. A query change, chat
switch or Escape invalidates late results and cancels further context paging.
The messenger interface is English;
conversation names and message content are not translated. Unread counts use circular
badges in Catppuccin Macchiato Yellow (`#eed49f`). Message times sit at the bottom
right inside each bubble. Read receipts appear below the bubble, resolving names
from the public API's `seen` participant map (or the contact in a one-to-one chat).
Missing receipts stay hidden; an anonymous receipt is labeled `Read` without
guessing who read it. Delivery success alone never counts as a read receipt.
The current user's own receipts are hidden on every network; anonymous receipts
on received messages are hidden too. Named readers use the same public API data
on all networks, subject to what each bridge and conversation actually provide.
In Telegram private conversations, the contact's latest confirmed read marker also covers earlier sent messages;
newer messages and pending/failed sends are not marked read by inference. Group
readers are shown only when Beeper includes them in that message's `seen` map.
Message bubbles have a small tail and the sender's name inside. Received messages
have a circular participant photo beside them (initials when the API provides no
photo); sent messages align to the right margin without a self avatar. The
tail is a curved vector path rendered with Qt's native CurveRenderer for smooth
edges at any display scale. Group headers show the public API's participant
total, never the length of a potentially partial participant list; when the
total is unavailable, the subtitle stays generic.
The messenger is borderless throughout: selection and keyboard focus use fills.
Account connection problems add a red `!` badge to the network selector and
temporarily use Catppuccin Red for the affected accounts' conversation accents,
avatar network badges, sent bubbles and composer controls. `All` warns if any
account has a problem; other healthy accounts keep their normal colors. A lost
connection to Beeper affects every conversation. Account status is refreshed
every five seconds through the public accounts endpoint while connected, with
one shared request at a time. Recovery restores the normal palette automatically;
history backfilling and unrelated action errors do not trigger this warning.
The conversation list shows each network through its avatar badge, without a
repeated network label. The selected conversation, sent bubbles and composer
microphone/send icon use the conversation's platform color, even in All. The
top-left All logo alone keeps its Mauve accent. Network accents use Catppuccin
Macchiato: Sapphire for Telegram, Green for WhatsApp, Pink for Instagram, Teal
for SMS and Blue for Signal; unknown platforms use a neutral fallback. Sent
bubbles keep dark text and controls for contrast; active recording retains
its red stop indicator.

Conversation pages load automatically near the bottom of the sidebar, including
when the network/search filter leaves it empty. Older messages load near the top
of the history without moving the message being read. Sidebar selection uses chat
IDs without native current-item tracking: background activity can reorder chats
without scrolling back to the selected conversation. Explicit navigation cancels
pending wheel motion before revealing a row; opening a modal stops that motion.
No manual load-more actions
or permanent keyboard/status footer are shown, with help under `?` and closing
under Escape / Cmd+D. Enter, `l`, `:` and right-click never open an action menu.
Ctrl+wheel over the conversation and Ctrl+plus/minus change only message text and
the composer (14–36 px, 2 px steps); Ctrl+0 resets it. The sidebar, header and bar
keep their normal sizes. The setting is shared across monitors and retained on
live Quickshell reloads. Notifications never render inside the chat and do not
take its typing focus; their usual Escape dismissal remains available.

Sending successfully always returns that conversation to the latest message,
without scrolling another chat if you switched while the request was in flight.
The composer is one line (48 px at the default font size) at rest and grows with
multiline text. Its caret is 3 px wide and follows the platform blink interval.
The circular smiley at the left opens an offline emoji grid with English/French
search. Choosing an emoji inserts it at the saved caret or replaces the selected
text, then restores typing focus without sending. Escape closes the picker first.
The Unicode Emoji 17.0 / CLDR 48 catalogue and license are included in
`features/messenger/BeeperEmojiData.js`; `generate-emojis.mjs` beside it prints
its regeneration patch. Its right-hand microphone crossfades to Send when text or an
attachment is ready, and becomes Stop while recording. There is no attachment
button; files remain available through paste and drag/drop.
Replies quote their original author/text above the body, both incoming and
outgoing, and in the composer before sending. Quotes keep a dark opaque background
tinted with the original author's accent, a matching name/stripe and secondary
text, including inside sent bubbles with a network-colored background.
Off-page originals are fetched
through the public retrieve-message endpoint, not by loading every history page.
Unavailable/deleted originals are labeled explicitly; resolving a quote does
not move the reading position or leave a newly sent reply below the viewport.

Native keyed list models apply refreshes incrementally so scrolling and media
players are not restarted by unchanged snapshots. Restoring a reading anchor
never cancels an ongoing wheel/touchpad gesture. Pagination is throttled during
scrolling rather than postponed until the gesture ends. Mouse dragging is not
used to scroll desktop lists; wheel, trackpad, scrollbar and Vim keys remain.
Ctrl+D/U use Qt's native animated half-page movement. These policies are local
to the messenger and do not change Hyprland's input configuration.
Wheel input uses Qt's usual distance (`wheelScrollLines × 24`, normally 72 logical
pixels per notch) and a retargetable 150 ms ease-out. Rapid events accumulate
distance; there is no ×4.5 cadence multiplier or distance-dependent flick tail.
Trackpad pixel deltas keep the platform's motion, and Ctrl+wheel remains text zoom.

The history uses `BeeperHistory`, a Flickable with exact message layout heights.
This avoids the variable-delegate content-height estimate that makes ListView
scrollbar thumbs resize while scrolling. Layout items remain for loaded messages;
avatars, media loaders and quote fetching are enabled only near the viewport.
The scrollbar may change when content is actually loaded or resized, not just
because a different-height message enters view. Times/reactions are inside the
bubble, with 12 logical pixels between bubbles and unchanged text sizes.
Received message bubbles, the composer and the conversation sidebar share the
opaque Macchiato Base background (`#24273a`, `Theme.surface`). Received sender names
keep their colors; selection adds a 12 px dot in the conversation's platform color
outside the bubble, on the right of received messages and the left of sent ones.
It is vertically centered, with a 6 px gap, and does not change the message layout
or background.

References: [Qt wheel implementation](https://github.com/qt/qtdeclarative/blob/v6.11.2/src/quick/items/qquickflickable.cpp),
[Chromium's bounded scroll durations](https://github.com/chromium/chromium/blob/main/cc/animation/scroll_offset_animation_curve.cc),
[Qt's variable-height scrollbar warning](https://doc.qt.io/qt-6/qml-qtquick-controls-scrollbar.html#varying-delegate-sizes).

Images/GIFs and audio/video controls are drawn directly inside the message
bubble, without an extra media card. Bubble width follows the widest required
content (text, quote, media, link or timestamp), capped by the available row
width. Visual previews keep their aspect ratio and fit within 250 px of height;
portrait photos never force a full-width bubble. The [public attachment `size`](https://developers.beeper.com/desktop-api-reference/resources/chats/)
provides dimensions before loading; decoded dimensions fill in missing metadata
and survive offscreen unloading, so revisiting a message does not resize it.
Audio-only bubbles are compact (up to
420 px), with play/pause, a seekable amplitude waveform, time and playback speed. The seek
slider deliberately ignores wheel input so scrolling over it keeps scrolling
the conversation. `BEEPER_PREVIEW_MEDIA=1` adds a silent fictional audio item
to the design preview; its waveform is explicitly fictional. Real waveforms are
computed by the Go backend from decoded audio, cached in memory, and fall back
to a thin track if analysis is unavailable. FFmpeg is an explicit backend runtime
dependency, not a patch to Beeper or Quickshell.

The native QML frontend talks to the persistent `quickshell-beeper` Go process.
Beeper Desktop is the local API provider and must remain running. Create an
API access token in Beeper's integration settings and enter it in our connection
screen; it is stored in GNOME Keyring, never in Nix. Disable Desktop notification
alerts and sounds in Beeper's settings without muting every conversation.
Our Go process creates the notifications, and their actions open our panel.
Original Beeper notification cards are suppressed while our client is connected.
While the messenger is open, chat arrivals from every conversation play their sound
without showing a banner on any monitor, including arrivals in the selected chat.
Opening the messenger also removes an existing chat card without interrupting its
sound. These arrivals are not queued for display after closing the chat. Other
application notifications remain visible; DND, muted chats and silent hints retain
their usual sound policy.

Home Manager starts Desktop as the user-session `beeper.service`, with restart
on failure. Enable its native minimized-launch preference and disable quit-on-close
once; see [the Beeper service guide](../home_manager/beeper/README.md) for the
first handover and diagnostics. The service does not rewrite Beeper preferences
or replace Desktop with a headless server.

Drafts and staged attachments persist in `~/.local/state/quickshell-beeper`.
The package includes Qt Multimedia for native image, GIF, audio and video views
and voice recording. A demo preview uses fictional conversations without API
access; its entry point is `preview.qml`, with its implementation in
`features/messenger/MessengerPreview.qml`. The
[Go backend README](../tools/quickshell/beeper/README.md) describes protocol,
credential handling and backend verification.

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

`features/keyboard/KeyboardCheatsheet.qml` receives ordered Hyprland custom events
from `../home_manager/hyprland/bindings.nix`; release bindings also work across
submaps and modifier changes. Reloading the compositor config or changing
submaps closes the sheet.
`features/keyboard/KeyboardSheet.qml` renders the diagram, while
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

`../home_manager/hyprland/lafayette.nix` fetches the official 0.9 symbols with a
fixed hash and compiles a standalone XKB keymap for Hyprland's `input.kb_file`. No firmware
changes, system XKB overwrites or custom Compose table are needed.
To restore the previous layout, remove `kb_file` from `settings.nix`, set
`kb_layout = "fr"`, `kb_variant = "us"`, keep `compose:caps`, and update the
diagram. The Cmd+apostrophe sheet shortcut works with either layout and avoids
arming Lafayette's one-shot accent latch when opening the sheet.

From the repository root, run
`node desktop/tests/keyboard-symbols_test.mjs KEYMAP [PYTHON] [LIBXKBCOMMON]`
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
