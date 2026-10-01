# System statistics

`quickshell-system-stats` is a persistent Rust process emitting one JSON object
per second: `cpu`, `memory`, `disk`, `brightness`, `system`, `usbDevices`, or `error` on a failed sample.
`../../../packages/quickshell/system-stats.nix` builds it without any runtime
command wrapper or Python dependency.

CPU and memory come from `/proc/stat` and `/proc/meminfo`; internal panel
brightness comes from `/sys/class/backlight`. Disk usage uses `statvfs` on `/`
and is refreshed every 30 seconds. Percentages preserve Python's ties-to-even
rounding. A missing backlight reports zero; hotplug and transient read errors
are retried, and a closed stdout pipe stops the process cleanly.

`usbDevices` lists `vendorId`, `productId` and `serial` from
`/sys/bus/usb/devices` on each sample. The battery capsule uses the keyboard's
USB identity to detect when it is plugged into this computer, including through
a hub. Bluetooth battery percentages alone do not report charging for Agar BLE.
Missing USB entries are skipped; unplugging removes the device on the next sample.

The additive `system` object supplies `cpuName`, `cpuFrequencyMHz`,
`cpuTemperatureC`, `memoryUsedBytes`, `memoryTotalBytes`, `swapUsedBytes` and
`swapTotalBytes` for the central panel. Frequency is the mean of the available
logical-CPU MHz readings in `/proc/cpuinfo`, not a maximum/turbo frequency.
RAM usage is `MemTotal - MemAvailable`, so reclaimable cache is not counted as
unavailable memory. Memory values are bytes; the UI converts them to GiB.

CPU temperature comes only from recognized CPU hwmon drivers (coretemp,
k10temp, zenpower, cpu_thermal), preferring package/Tdie sensors and taking
the maximum across packages. Missing or invalid optional sensors produce
`null`, not zero, and do not stop the base telemetry. No external command or
additional daemon is used. GPU telemetry has its own native Rust NVML collector
in `../gpu-monitor/`, shared by the side bubble and central panel.

## Panel-only process lists

The same persistent process accepts a newline-delimited unsigned generation
number on stdin. `0` (the default) disables process scanning; a positive number
starts a new panel subscription. EOF also disables scanning. The controller
thread blocks on stdin, with no polling or extra subprocess.

While subscribed, one scan of `/proc/PID/stat` every two seconds supplies both
CPU and RAM top fives in an additive `top` object. `generation` identifies the
request; `cpu` and `memory` contain at most five rows (`pid`, `name`, `usage`
or `memoryBytes`). A row's CPU percentage is the recent utime+stime delta over
monotonic elapsed time: 100% is one logical CPU and multicore processes may
exceed 100%. This differs from the total-machine CPU percentage in the bubble.
RAM is RSS in bytes, not virtual allocation or PSS; shared resident pages may
appear in more than one process. Do not sum these rows to derive global RAM.

The first CPU sample is null until the next scan establishes a delta. Closing
or changing the generation drops all baselines. PID/start-time checks handle
PID reuse; inaccessible, exited or malformed processes are skipped. Process
names prefer executable basenames, resolving only the displayed winners;
command lines and their potentially private arguments are never read.
List failures do not break global telemetry. There is no process scan while
the panel is closed, and no graph history is retained.

From the repository root, in the existing `nix develop .#rust` shell:

```sh
cargo test --manifest-path tools/quickshell/system-stats/Cargo.toml
cargo clippy --manifest-path tools/quickshell/system-stats/Cargo.toml --all-targets -- -D warnings
```

Tests cover counter resets, guest accounting, rounding, disk caching, missing
or malformed files, backlight removal/reappearance and the JSON stream lifetime.
The stream test only reads real telemetry; fixture tests never write procfs/sysfs.

## On-demand storage breakdown

The same package also installs `quickshell-storage`. This is an independent,
one-shot metadata scan, never part of the one-second telemetry loop:

```sh
quickshell-storage --home /home/ian --output /run/quickshell-storage/report.json
```

The output parent must already exist. A temporary file in that directory is
atomically renamed to the requested report, with mode 0644. The old report
survives a failed or interrupted scan. `--root /absolute/fixture` restricts
traversal to a fixture directory for diagnostics; capacity still describes the
filesystem containing that directory. Invalid, relative and symlink output
destinations are rejected. The collector has no cleanup or deletion operation;
it only removes its own temporary report if publication fails.

The schema is `schemaVersion: 1`, a completion-time `measuredAt` in epoch
milliseconds, `durationMs`, `estimated: true`, `filesystem`, and `disk` containing
`totalBytes`, `usedBytes` and `availableBytes` from statvfs. `categories` always
contains `docker`, `nix`, `applications`, `personal`, `vm` and `other`, each with
`bytes` and `partial`. Applications additionally contains `cacheBytes` and
`dataBytes`. `errors` contains an aggregate `count` and a generic `message`;
private file names never enter the report. A wholly inaccessible category has
null bytes, while a partially measured category is explicitly a lower bound.

Sizes use allocated blocks (`st_blocks * 512`), including sparse-file handling.
Directory descriptors opened with `O_NOFOLLOW` prevent symlink traversal even
if a directory is replaced during the scan. Regular-file contents, Docker
sockets, device nodes and VM disk contents are never opened. The mount table
restricts traversal to the root backing filesystem, including its Btrfs
subvolumes, excluding external and pseudo filesystems. Inode/device pairs are
globally deduplicated for files and directories. `/home`, `/var` and `/nix` are
visited before `/persist`; persistence aliases are classified using their
canonical home/system location.

Docker includes `/var/lib/docker`, `/var/lib/containerd` and per-user
`.local/share/docker`. Nix includes `/nix/store`. Applications includes hidden
home directories and `/var/lib/flatpak`, with `.cache` broken out separately.
The NixOS checkout and chezmoi source directories remain personal projects.
VMs includes libvirt image directories and `VirtualBox VMs`. Other files go
to `other`. Only a complete scan whose category sum is below actual filesystem
usage adds the remaining allocation to `other` (metadata, inaccessible-to-the-
namespace snapshots and similar filesystem overhead). No category is scaled
down if estimates exceed actual usage.

These remain estimates on Btrfs: separate inodes can share extents and a running
filesystem changes during traversal. The report is not a promise of reclaimable
space. The UI must use the category sum for the breakdown and display actual
free/used capacity separately. The intended system service supplies read access
to Docker/VM directories, resource limits and timeout; an ordinary user scan
reports denied paths as partial, never silently as zero.
The service also freezes mount propagation during a scan. Standalone diagnostic
runs use a mount-table snapshot, so mounts should not be changed while running.
