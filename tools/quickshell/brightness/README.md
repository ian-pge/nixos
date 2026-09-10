# Quickshell brightness

An independent Cargo project for `quickshell-brightness`, packaged by
`../../../packages/quickshell/brightness.nix`. It accepts a monitor connector,
percentage-point steps as JSON and an optional previous JSON result.

Internal panels use `brightnessctl`; external displays use `ddcutil` with an
identity resolved from the connector, model and serial number. Quickshell owns
the cached bus and discards it when the monitor topology changes. Recently
verified levels are reused for two seconds. Each burst clamps after every step,
preserves direction reversals and performs at most one verified DDC write.
There is no polling or driver override.

From the repository root, inside `nix develop .#rust`:

```sh
cargo test --manifest-path tools/quickshell/brightness/Cargo.toml
cargo clippy --manifest-path tools/quickshell/brightness/Cargo.toml --all-targets -- -D warnings
```

Tests use fake monitor commands and never touch real hardware. They cover
rounding, clamping, monitor identity, stale caches, internal panels, ambiguous
displays and failed writes. Runtime commands are added only by the Nix wrapper.
