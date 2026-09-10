# Chrome tabs

`quickshell-chrome-tabs` combines the TabCtl adapter and favicon cache in one
Rust executable. It is packaged by `../../../packages/quickshell/chrome-tabs.nix`
and installed alongside the existing TabCtl native messaging host by
`../../../home_manager/tabctl.nix`.

The existing commands and Quickshell JSON protocol are preserved:

- `list`: calls `tabctl --format json list`, adds `iconPath` to each tab and emits
  `{ "ok": true, "tabs": [...] }` or `{ "ok": false, "tabs": [], "error": ... }`.
- `activate ID`: calls `tabctl activate --focused ID` and reports `{ "ok": true }`
  or `{ "ok": false, "error": ... }`.
- `close ID`: similarly delegates to `tabctl close ID`.
- `status`: passes through native TabCtl output and exit status.

Favicons come from `$XDG_CONFIG_HOME/google-chrome/Default/Favicons` (default
`~/.config`). SQLite opens the live database read-only with no lock wait, without
declaring it immutable. Missing/locked databases, incompatible schemas and
unavailable icon caches leave `iconPath` empty instead of breaking tab listing.
The largest bitmap is preferred, then the newest at equal size. Files use the
existing SHA-256 names in `$XDG_CACHE_HOME/quickshell/chrome-favicons` (default
`~/.cache`), mode 0600, with unique temporary files and atomic replacement.

The Rust binary links the Cargo-pinned bundled SQLite library. The only external
runtime command is the existing TabCtl package. No Python or jq is needed by
this adapter. The shared Rust development shell already provides the C compiler
needed to build bundled SQLite.

From the repository root, inside `nix develop .#rust`:

```sh
cargo test --manifest-path tools/quickshell/chrome-tabs/Cargo.toml
cargo clippy --manifest-path tools/quickshell/chrome-tabs/Cargo.toml --all-targets -- -D warnings
```

Tests create isolated SQLite fixtures and fake TabCtl commands. They cover
read-only access, locked/corrupt/missing databases, bitmap selection, concurrent
cache writes, malformed JSON, argument forwarding, status passthrough and
cancellation. They never read or manipulate the user's real Chrome tabs.
