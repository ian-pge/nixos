# System statistics

`quickshell-system-stats` is a persistent Rust process emitting one JSON object
per second: `cpu`, `memory`, `disk`, `brightness`, or `error` on a failed sample.
`../../../packages/quickshell/system-stats.nix` builds it without any runtime
command wrapper or Python dependency.

CPU and memory come from `/proc/stat` and `/proc/meminfo`; internal panel
brightness comes from `/sys/class/backlight`. Disk usage uses `statvfs` on `/`
and is refreshed every 30 seconds. Percentages preserve Python's ties-to-even
rounding. A missing backlight reports zero; hotplug and transient read errors
are retried, and a closed stdout pipe stops the process cleanly.

From the repository root, in the existing `nix develop .#rust` shell:

```sh
cargo test --manifest-path tools/quickshell/system-stats/Cargo.toml
cargo clippy --manifest-path tools/quickshell/system-stats/Cargo.toml --all-targets -- -D warnings
```

Tests cover counter resets, guest accounting, rounding, disk caching, missing
or malformed files, backlight removal/reappearance and the JSON stream lifetime.
The stream test only reads real telemetry; fixture tests never write procfs/sysfs.
