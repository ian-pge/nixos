# Quickshell GPU telemetry

An independent Rust collector, packaged by `packages/quickshell/gpu-monitor.nix`.
It replaces the upstream `gpu-usage-waybar` executable, wrapper and patch.
`StatusData.qml` still launches one shared `quickshell-gpu-monitor` process;
the side bubble and central System panel consume the same JSON stream.

## Collection

- Discover NVIDIA display/3D PCI devices through sysfs, excluding HDMI audio
  functions. Select the first PCI address in sorted order. This backend targets
  the NVIDIA laptop GPU; AMD/Intel telemetry is not implemented.
- Read that device's `power/runtime_status` before initializing NVML and before
  each sample. Suspend and transitions emit `Off` with null measurements.
  Unknown or unreadable power states emit unavailable data without calling NVML.
- Initialize NVML lazily via `nvml-wrapper`, loading the library matching the
  running NixOS driver at `/run/opengl-driver/lib/libnvidia-ml.so.1`.
  Normal initialization is intentional: `NO_ATTACH` prevented access even to
  an active GPU in hardware testing with NVIDIA driver 610.57.04.
- Address the selected GPU by PCI ID, cache its name, and query GPU load,
  temperature and used/total VRAM. Process details are opt-in while the panel
  is visible (see below). No `nvidia-smi`, shell wrapper, config file,
  tooltip generation, encoder polling or second sampler.
- Sample once per second and flush each line. Driver/library failures emit
  unavailable data and retry initialization after 30 seconds, without exiting.
  A changed/missing selected PCI device clears the cached identity and backend.
  Closing the output pipe exits cleanly.

The sysfs power check and cached identity are ideas retained from the
[previous collector](https://github.com/PolpOnline/gpu-usage-waybar/blob/v0.1.23/src/nvidia.rs).
The power check avoids querying a GPU observed asleep; it is not an atomic
kernel guarantee against a concurrent power-state change. It never writes power
settings. NVML and the NVIDIA driver remain runtime dependencies; only the
collector is implemented locally.

## Output contract

One JSON object per line, with `text` for the bubble and `gpu` for the panel:

```json
{"text":"4%|13%","gpu":{"poweredOn":true,"name":"NVIDIA GPU","usage":4,"temperatureC":42,"memoryUsedBytes":536870912,"memoryTotalBytes":4294967296}}
```

All GPU fields use camelCase. Memory is in bytes; usage is a percentage.
Unsupported measurements are `null`, never fabricated zeroes. A suspended GPU
has `poweredOn: false`, cached name if available, and all measurements null.
An absent GPU, unreadable power state or driver error has `text: "--"`,
`gpu: null` and a diagnostic `error` string. Thus the existing QML invalidates
old readings instead of presenting stale values.

## Panel-only process lists

Stdin accepts the same generation protocol as `../system-stats/`: `0` disables
the top list, a positive integer starts a new subscription, and EOF disables
it. The default is off. Global metrics stay at one second; process queries
run at most once every two seconds while subscribed, after checking that
the selected card is active. A sleeping card is never queried for its top.

The optional `top` object carries `generation`, `sort` (`gpu` or `vram`) and
up to five `rows` with `pid`, `name`, `usage`, `memoryBytes`. Graphics and
compute process lists are merged by PID without double-counting VRAM.
Recent NVML SM (3D/compute) samples determine the GPU order; old samples and
exited PIDs are excluded from utilization ranking. Missing utilization is
null, not a guessed zero. Unsupported utilization explicitly selects VRAM
ordering. An empty sample buffer is not treated as a driver failure.
The selected names are read from executable basenames or comm, never argv.
Optional query failures appear in `top.error`, leaving global metrics intact.

Closing/reopening resets the time window and generation; QML ignores old
queued responses and expires lists independently from global readings.

## Verification

From the repository root:

```sh
nix develop .#rust
cargo test --locked --manifest-path tools/quickshell/gpu-monitor/Cargo.toml
cargo clippy --locked --manifest-path tools/quickshell/gpu-monitor/Cargo.toml --all-targets -- -D warnings
nix build --no-link .#quickshellGpuMonitor
```

Tests use a fake PCI tree and backend, requiring neither a GPU nor its driver.
They cover cold suspend, power transitions, missing/unsupported measurements,
driver recovery, PCI selection/hotplug, the QML contract and stream lifetime.
The Nix build runs them as well.

`nix run .#quickshellGpuMonitor -- --once` prints one real sample without
activating the configuration. After a rebuild, use `quickshell-gpu-monitor --once`;
`--sysfs-root DIRECTORY` permits an isolated PCI fixture for diagnostics.
An unavailable sample is still valid JSON and exits successfully: check `gpu`
and `error`, not just the process exit code, when verifying live telemetry.
