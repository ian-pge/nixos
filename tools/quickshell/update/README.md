# Quickshell update

One Cargo project provides `quickshell-update-checker`,
`quickshell-update-installer` and `quickshell-update-diff`.
`../../../packages/quickshell/update.nix` builds them once and gives each command
its runtime tools. The same recipe packages `activate-system.sh` as an immutable,
root-only helper invoked through systemd `run0`.

The checker structurally compares lockfiles, invalidates its cache when the
flake changes and atomically saves the candidate lock. The installer reuses
that candidate only if both fingerprints match, builds once, displays the
closure diff and waits for `install` on stdin before requesting authorization.
The diff reads Nix JSON format 2 metadata and compares package versions and
selection changes.

The installer and checker share a lock with the Nix cleaner. A failed or
cancelled update restores the original lockfile. Boot installation persists a
reboot-required target until that generation runs. Once privileged installation
starts, the installer waits for its outcome before handling cancellation.
The `@@QS_UPDATE@@` JSON events and Quickshell-facing command names are unchanged.

From the repository root, inside `nix develop .#rust`:

```sh
cargo test --manifest-path tools/quickshell/update/Cargo.toml
cargo clippy --manifest-path tools/quickshell/update/Cargo.toml --all-targets -- -D warnings
bash tools/quickshell/update/update-cache_test.sh
```

Tests cover cache reuse/invalidation, version comparisons, rollback, failed
builds, EOF, signals and privilege-boundary validation using fake commands.
Nix uses a dummy store closure; local CLI tests use `/run/current-system` only
as a read-only path fixture. No test performs a real update or activation.

`QS_UPDATE_CHECKER_BIN` and `QS_UPDATE_INSTALLER_BIN` can point the shell harness
at another build of the **unwrapped** Rust binaries. Production Nix wrappers
prepend real runtime tools and must not be used with these mocks.
