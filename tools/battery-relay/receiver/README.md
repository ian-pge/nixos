# Battery Relay receiver

This crate builds two independent runtime commands. `battery-relay-receiver`
serves phone/Fitbit; `fast-pair-battery` observes the Pixel Buds' encrypted
advertisements without connecting. The latter reads a private Account Key from
a runtime file and does not need the phone. The manual pairing tool is separate:
[complete pairing and decoding procedure](../pairing/README.md).

Foreground Linux BLE central, using BlueZ D-Bus through
[BlueR](https://github.com/bluez/bluer). It reads and subscribes to the Android
application's GATT server. No native pairing, encryption requirement, pairing
agent, trust changes, root access, audio profile commands or adapter power changes.
Home Manager installs the packaged command; the shared Quickshell power
controller starts one instance when its public service UUID is configured.

## Build and test

From the repository root:

```sh
nix develop .#rust --command cargo test --locked --manifest-path tools/battery-relay/receiver/Cargo.toml
nix develop .#rust --command cargo build --locked --manifest-path tools/battery-relay/receiver/Cargo.toml
tools/battery-relay/receiver/target/debug/battery-relay-receiver --check
```

`--check` reads adapter properties only. It does not scan, connect or change
settings. Hardware and background behavior require separate real-device tests.

## Start

In the Android app, configure the PC's Bluetooth address, activate the relay and
copy its public installation identifier. No system pairing is necessary.
Then use that identifier (not the phone's changing BLE address):

```sh
tools/battery-relay/receiver/target/debug/battery-relay-receiver --service PHONE_SERVICE_UUID
```

An optional `--adapter hci0` chooses the PC adapter.
`--service PHONE_SERVICE_UUID --discover` scans for that service for 15 seconds
and lists live candidates without connecting. Normal mode reuses an existing
connection to that exact service or performs scoped LE discovery and connects.
The phone's private advertising address may change; its installation UUID does
not change across app updates or normal restarts.

## Security boundary

This is deliberately **unencrypted and unpaired**, by explicit owner choice.
The public installation UUID selects the intended app but is not authentication.
The Android PC-address filter is also spoofable. A nearby observer may intercept,
track or impersonate the exchange. No credentials, account tokens or control
commands belong on this service. Existing system pairings are not deleted.

The receiver rejects blocked/disconnected devices and malformed snapshots.
It does not connect a phone merely because its display name matches.
The phone advertises its public service UUID, not battery values or its name.
Reads and subscription writes are ordinary GATT operations; indications are
acknowledged by the Bluetooth stack, not by the final widget.

## Protocol and output

See [../PROTOCOL.md](../PROTOCOL.md) for the canonical 12-byte payload. The
characteristic UUID is `d973f2e0-b19e-4f19-9a67-6c414c65f802`; the primary
service UUID is installation-specific. This build accepts phone and Fitbit snapshots.
Version 0.4 removes the former Google-widget characteristic. Earbuds are served
only by the independent `fast-pair-battery` process. Its continuous LE discovery
uses live BlueZ signals, not cached initial device properties. An account-key
filter match is required before decoding; unrelated devices are ignored.

```sh
tools/battery-relay/receiver/target/debug/fast-pair-battery \
  --key-file "$HOME/.local/state/battery-relay/pixel-buds.account-key" --check
tools/battery-relay/receiver/target/debug/fast-pair-battery \
  --key-file "$HOME/.local/state/battery-relay/pixel-buds.account-key" --duration 30
```

Omit `--duration` for the supervised reader used by Quickshell. It emits changed
values immediately, unchanged observations at most every 30 seconds, and clears
stale components after 180 seconds using a clock that includes suspend. It has
no phone-session requirement, connection/pairing code or native battery fallback.
Exit 78 denotes an invalid/missing private key file; the view does not restart
that configuration in a loop. Runtime failures use the normal restart delay.
The Account Key must be a user-owned regular 16-byte file with private permissions,
outside the Nix store; it is never printed or passed as a command-line value.

Stdout is NDJSON; diagnostics go to stderr:

```json
{"event":"connection","connected":false}
{"event":"connection","connected":true}
{"event":"battery","device":"phone","percent":73,"pluggedIn":true,"charging":false,"updatedAt":1700000000000,"receivedAt":1700000001234}
{"event":"connection","connected":false}
```

Only a parsed phone snapshot marks the relay connected. Another Bluetooth
profile's connection cannot substitute for a battery reading. Initial read,
battery changes and a best-effort 60-second heartbeat provide updates.
After 180 seconds without a phone snapshot, the receiver invalidates the session
and attempts reconnection. Android Doze may defer the heartbeat.

Disconnect, blocking, adapter loss, service disappearance or graceful shutdown
invalidate readings. Consumers must also invalidate on EOF. Never turn unknown
data into zero or invent a charging state from 100%. Source timestamps are kept
separate from PC receipt times; the clocks need not be identical.

Ctrl-C/SIGTERM release this process's notification/discovery sessions.
An existing BLE link can outlive the process because BlueZ or other clients may
still use it; subsequent runs reuse that service instead of opening a second
connection to the phone's new advertising address.

Stdout uses a bounded worker queue and two-second output deadline. A stalled
consumer cannot freeze the Bluetooth reactor. No battery cache is written to
disk; consumers must discard an incomplete final JSON line.

Unit tests cover the wire format, unknown values, lifecycle expiry, service
selection, blocked links and output failures. On the Pixel, real reception,
receiver restart and recovery after an actual BLE disconnect have been tested.
The owner also confirmed automatic reconnection after a real phone reboot.
Long-term idle power and out-of-range recovery remain unverified.

### Connection recovery (0.2.1)

Android can remove/recreate its GATT service while the underlying LE link stays
connected, notably during an app update. A Bluetooth connection alone is not
proof that the battery subscription still works. A removed service/UUID, failed
subscription/read, expired heartbeat or timed-out operation invalidates the
session. GATT operations have a 15-second deadline; device lookup has a
45-second total deadline.

On such a failure, the receiver may release **only the device selected through
the configured service UUID in that session**, and only if its address is random,
it is connected, unpaired, untrusted and not blocked. All property checks must
succeed. This uses BlueZ's normal device disconnect API; it releases that LE
link, not merely one characteristic. It never disconnects a public-address,
paired/trusted or unrelated device, removes a device, resets the adapter, or
changes audio profiles. A fresh receiver process is then started by Quickshell's
existing five-second supervisor. This also clears stuck client-side notification
sessions instead of reusing them forever.

Diagnostics are now collected by Quickshell from stderr. The read-only
`qs ipc -c top-bar call topbar batteryStatus` command reports the actual bar's
connection, age and visible battery readings without starting a second receiver.
The optional hardware soak test uses `BATTERY_RELAY_SOAK_MS=240000` and
`BATTERY_RELAY_REQUIRE_FITBIT=1` to require four minutes of uninterrupted phone
updates and a current Fitbit reading; any disconnect resets the stable interval.
It does not itself interrupt devices or install an APK.

Version 0.2 accepts both phone and Fitbit packets. Only phone packets establish
or extend transport liveness; Fitbit retains its original Google Health sync
timestamp, with null plugged/charging fields. An all-unknown Fitbit packet
withdraws its previous reading. Quickshell additionally expires cloud readings
after six hours. Real Fitbit reception has now been verified following owner
OAuth configuration; the separate protocol/parser/UI unit tests use fictitious
data, not a connected Fitbit account.
