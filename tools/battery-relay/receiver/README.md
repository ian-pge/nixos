# Battery receivers — 0.6.0

Two independent supervised commands share the passive BlueZ transport in
`src/observer.rs`:

- `battery-relay-receiver --service PHONE_UUID`: Android's non-connectable v2
  phone/Fitbit announcements.
- `fast-pair-battery --key-file /absolute/private/key`: Pixel Buds BATT
  advertisements, decoded with the PC's existing private Account Key.

Neither runtime reader starts discovery, connects, pairs, subscribes to GATT,
disconnects devices or changes adapter/trust/audio settings. The former GATT
receiver, heartbeat probe, connection-reset policy and active discovery code have
been removed, not kept as fallback. The manual Fast Pair provisioning utility
remains separate: [pairing and decoding procedure](../pairing/README.md).

## Build and verify

```sh
nix develop .#rust --command cargo test --locked --manifest-path tools/battery-relay/receiver/Cargo.toml
nix develop .#rust --command cargo clippy --locked --manifest-path tools/battery-relay/receiver/Cargo.toml --all-targets -- -D warnings
nix build .#batteryRelayReceiver --no-link --print-out-paths
```

Phone `--check` reads adapter/API support only, no monitor or scan.
Earbud `--check` validates the private key only.
Both support `--adapter hci0` and optional `--duration 1..3600` for bounded
diagnostics. Normal bar processes omit duration. Invalid options/key configuration
return 78. Both QML consumers stop retrying on that configuration error until
their configuration changes or they are explicitly re-enabled; runtime failures
still use Quickshell's five-second supervisor.

## Android setup and upgrade

Install Android BLE **0.6.1** using the existing signing identity (same v2 payload).
Activate the relay; there is no PC Bluetooth address to enter. Copy the public
installation identifier from Settings into the PC configuration if not already
configured. The same installation UUID is retained across this update, along with
Google authorization and auto-resume preference. The completed widget/PC-address
migrations and their dedicated cleanup test were retired in 0.6.1; the current
permission safeguards remain tested. No legacy data reader is restored.

The phone advertises both readings directly and cannot confirm PC reception.
Android's controller repeats the advertisement approximately every second.
The app updates it on battery/cloud changes: no phone heartbeat timer, GATT
server, indication queue, wake lock or exact alarm. Google Health fetching remains
optional, every 15 minutes best effort. Fitbit's source date is retained with
one-second wire precision.

See [PROTOCOL.md](../PROTOCOL.md) for the 30-byte AD structure, shared vectors,
decoding, unknown values and privacy boundary. This is deliberately unencrypted
and unauthenticated, for battery telemetry only.

## Presence, freshness and lifecycle

BlueZ's AdvertisementMonitor API is experimental in 5.87. Nix enables
`hardware.bluetooth.settings.General.Experimental = true`, not KernelExperimental.
Both readers require `or_patterns`; there is **no active-scan fallback**.

BlueZ 5.87 software matching strips service UUIDs before comparing patterns,
unlike kernel/controller matching. Each source supplies two OR prefilters:
raw UUID+version and payload version. The common observer subsequently selects
the exact service UUID; the earbud decoder also checks its Account Key filter
and decrypts. This is a documented compatibility adaptation.

- DeviceFound is required before reading that device's cached ServiceData.
- DeviceLost removes only that address, with a requested 180-second absence
  timeout. A newer advertising address remains independent.
- Changes are reported immediately after observation; unchanged monitor state is
  reported every 30 seconds. This is a **PC status report**, not a new phone/cloud
  measurement or a claim of a newly received radio packet.
- Observation/source timestamps do not advance with status reports.
- Quickshell expires a silent helper after 180 seconds. EOF, BlueZ replacement,
  adapter-off/removal and monitor release invalidate data.
- After a receiver-loop suspension ≥180 seconds, the fresh monitor must reestablish
  presence. CLOCK_BOOTTIME includes suspend.
- Bounded event queues, API timeouts and a two-second stdout deadline prevent a
  blocked consumer from silently freezing the radio loop.
- Phone/Fitbit output is atomic. Fitbit is hidden at six hours of source age,
  independently of radio presence. Unknown is never zero.

## BlueZ configuration history

Continuous active earbud discovery was isolated as the trigger of MX Anywhere 3S
reconnection failures. Both runtime readers now use passive observation.

Enabling experimental interfaces also enabled unrelated profiles. The `rap`
ranging plugin remains disabled; passive monitoring needs no ranging.
RAP exclusion alone did **not** repair the former connected phone relay:
authentication failures remained. Source inspection also found experimental MCP
reading Android's encrypted media attributes. This was another plausible cause,
not independently proven by disabling MCP. V2 does not connect at all, so those
GATT profile attachments are not required for battery reception.

NixOS sets bluetooth.service.restartIfChanged=false. Changing daemon options
requires the owner's rebuild and one manual `sudo systemctl restart bluetooth`;
no reader resets the adapter.

## Actual-bar checks

Prefer observing the real bar instead of starting additional receiver processes:

```sh
qs ipc -c top-bar call topbar batteryStatus
node desktop/tests/battery-relay-soak_test.mjs --seconds 420 --require-fitbit --require-no-discovery
```

Both modes must be passive. `phoneAgeMs`/`earbudAgeMs` are content-observation
ages and may grow with unchanged batteries. `phoneReportAgeMs`/`earbudReportAgeMs`
measure the helpers' status reports. `connected` is the UI property name for
phone presence, not an ACL link. Discovering must stay false with search panels closed.

Also test USB unplug/replug, mouse off/on on its original paired channel,
source stop/restart, distance loss/return, screen-off idle and reboot.
Never delete/re-pair the mouse or earbuds as a battery test.

Initial 0.6.0 hardware validation on 2026-10-21: APK updated in place and
MY_PACKAGE_REPLACED automatically resumed advertising with the screen dozing.
The actual bar received phone 100% / plugged / not actively charging, Fitbit 86%,
case/left/right 100%, with both monitors passive and Discovering=false.
The live stability/recovery results are recorded after those checks; unit tests
alone do not prove radio reliability or long-term power consumption.

Final live check (2026-10-21): the actual bar passed 180 uninterrupted seconds
with phone, Fitbit and earbud case present, both modes passive and Discovering=false
at every sample. Six phone status reports and five earbud status reports arrived;
maximum report ages were 30.292 s and 30.296 s. The unchanged source dates did not
advance. The Pixel was dozing and USB-powered; this is not a deep-idle/autonomy test.
BlueZ reported the advertising phone unconnected and unpaired, and the former
authentication errors stopped after deployment. A previous 420-second run was
interrupted after more than 306 seconds by an unrelated Quickshell presentation
reload at 12:22:30, so it is **not** counted as a passing 420-second test. All
sources returned automatically afterward, and again after final reader activation.
Physical cable changes, a mouse power cycle, actual reboot and distance loss/return
still require owner confirmation; no simulated battery values were used as proof.

The phone runs BLE 0.6.0 (versionCode 13). The current bar uses the packaged 0.6.0
readers in a preview preserving the latest concurrent layout. Source packaging
is ready for the owner's normal NixOS rebuild; no system switch was performed.
The prior APK is backed up privately in Downloads/ble-passive-upgrade.krv3GY.

Offline validation: 26 receiver Rust tests, 10 provisioning-helper tests,
Clippy with warnings denied, 46 Android tests and Android lint/APK build passed.
QML phone data (13), earbud data (11), power/feature controllers (35) and the
passive-only wiring check passed. Both Nix packages built successfully.
The full desktop composition suite was also run: 23 passed / 15 failed on
layout/transition assertions (including compact capsule and surface bounds).
It is not reported as a passing integration suite; the battery-specific checks
and actual-bar observation are recorded separately. Unrelated layout edits
were not changed to make that suite pass.
