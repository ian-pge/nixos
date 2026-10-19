# Battery Relay receiver

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
service UUID is installation-specific. This build accepts phone snapshots only.

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
Long-term idle power, out-of-range recovery and reboot startup remain unverified.
