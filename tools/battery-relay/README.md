# Battery Relay

Local application for sending the Pixel's battery to this PC over a
dedicated Bluetooth Low Energy data service, independently of audio profiles.
No root, Android Studio, cloud relay, KDE Connect or Play Store publication is
required. The first version handles the **phone only**. Fitbit/Google Health,
OAuth and production Android signing are not implemented.

## Components

- `android/`: Kotlin app, battery change receiver and foreground `connectedDevice`
  service. It exposes a BLE GATT server, with low-power advertising while waiting
  for the PC and indications while subscribed. No scanning, wake lock or cloud.
- `receiver/`: Rust BLE central using BlueZ D-Bus. It finds the explicitly selected
  public installation UUID, subscribes and emits NDJSON for Quickshell.
  No pairing agent, bond/trust changes, adapter-power or audio-profile commands.
- [PROTOCOL.md](PROTOCOL.md): versioned 12-byte protocol and shared test vector.

`packages/battery-relay.nix` packages only the receiver sources, never Android
signing material. Home Manager installs it and passes the public UUID configured
at `programs.quickshell.phoneBatteryServiceUuid` to the Quickshell service.
The shared power controller starts exactly one receiver for all monitors.
The phone widget has no Bluetooth-battery/USB fallback. Other battery widgets
keep their own existing providers. Apply this wiring with the normal rebuild;
building individual packages does not activate the running desktop.

## Development environments

From the repository root:

```sh
nix develop .#android
cd tools/battery-relay/android
./gradlew --no-daemon testDebugUnitTest lintDebug assembleDebug
```

The environment supplies JDK 17 and an immutable Nix Android SDK (API 36,
build tools 35.0.0). Do not run SDK installation/update commands against the
Nix store. Add SDK versions to `dev-shells/android.nix` instead. The environment
also selects Nix's patched `aapt2` and caches Gradle downloads under
`${XDG_CACHE_HOME:-$HOME/.cache}/gradle`. Android Studio and emulator downloads
are unnecessary for this project.

The project pins Gradle 8.13 through its checked wrapper and distribution
checksum, and dependency artifacts through SHA-256 verification metadata. The
shell's Gradle is only a bootstrap tool. Development builds use
the local `.local/debug.keystore` so the signing identity survives reboots on
this impermanent system (the repository directory is persisted). That private
file is ignored by Git and must never be added to Nix sources. Create it once
from the repository root inside the Android development shell if missing:

```sh
umask 077
mkdir -p tools/battery-relay/.local
keytool -genkeypair -keystore tools/battery-relay/.local/debug.keystore \
  -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass android -keypass android \
  -dname 'CN=Android Debug,O=Battery Relay,C=FR'
```

This is a **development-only** signing identity with the standard debug
passwords; release distribution requires a separate protected key and build.

Receiver tests, without touching the radio:

```sh
nix develop .#rust
cargo test --manifest-path tools/battery-relay/receiver/Cargo.toml
cargo clippy --manifest-path tools/battery-relay/receiver/Cargo.toml --all-targets -- -D warnings
```

## On-device testing (requires the owner)

The Android APK is produced at
`android/app/build/outputs/apk/debug/app-debug.apk`. Installing it is a separate
step, never a side effect of entering the development shell or running tests.

1. Connect the Pixel with a data-capable USB cable, enable USB debugging and
   accept only this PC's debugging key. No bootloader unlock is needed.
2. Check `adb devices` and install the APK with `adb install -r` (same signing
   identity preserves app settings). Never uninstall another app to bypass a
   signing conflict. Alternatively transfer and install the APK manually.
3. In the app, configure this PC's Bluetooth address and activate the relay.
   Copy the public installation identifier displayed there; start the receiver
   with `--service UUID` (see `receiver/README.md`). No native pairing is needed.
   Existing Fitbit/phone and other Bluetooth associations must not be changed.
4. Check phone percentage, USB plug/unplug, full/not-charging distinctions,
   unknown values, out-of-range recovery, screen-off idle, app stop and PC reboot.
   No actual device reliability claim is justified by JVM/Rust tests alone.
5. Test music and calls remain on the phone. This protocol never connects audio,
   but an existing classic Bluetooth pairing can still do so independently.
   Do not change global audio roles as part of application initialization.

The USB connection is only for installation/debugging. The app should continue
to function after USB debugging is disabled. Initial activation is explicit:
once enabled, the relay resumes after Android reboot (first unlock) and after
an app update, using the saved PC address and installation identifier. The
standard `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` receiver starts the existing
`connectedDevice` foreground service; no pairing, wake lock, alarm or battery
optimization exemption is added. If Bluetooth is off, the service waits for it.
The app's Stop button and notification's Stop action disable this automatic
resume too. Missing Bluetooth permissions/configuration prevent resume. Android
force-stop or restricted battery settings can prevent delivery; reopen and
activate the app in that case. No restart loop bypasses these system decisions.

## Shell integration and remaining validation

Current mode is deliberately **unencrypted and unpaired**, as explicitly chosen
by the owner after the encrypted prototype failed. The public installation ID
and PC-address filter are not authentication. Nearby devices can observe,
track or imitate the exchange; only battery telemetry belongs on this service.

Device test, 2026-10-20 (Pixel 8 Pro / Android 17, BlueZ 5.87, Linux 6.18.56):
the PC received 95%, plugged and actively charging over BLE; the phone's native
battery reading independently matched. The LE link was not paired, bonded or
trusted. Receiver stop/restart and recovery after an actual BLE disconnect were
tested without a pairing prompt (the next reading was 96%, charging). Long-term
Doze behavior, power consumption and startup after reboot still need testing.

Autostart update, 2026-10-20: JVM tests, lint and APK build passed; installing the
update on the Pixel resumed the opted-in foreground relay through
`MY_PACKAGE_REPLACED`, without opening its activity. Pressing Stop persisted
`enabled=false`; another APK update then logged a skipped resume and left the
service stopped. The relay was then reactivated through its button; the PC's
existing receiver resubscribed and received 99%, plugged and charging. The same
startup receiver is registered for `BOOT_COMPLETED`.
This production phone rejects the documented
ADB synthetic boot broadcast, so that is not a substitute for a real reboot:
restart and unlock the phone without opening Battery Relay to validate it.

`desktop/features/power/BatteryRelayData.qml` consumes the receiver's NDJSON.
EOF, disconnect, malformed data and expired heartbeats clear the reading. The
phone dial follows the existing accessory visibility policy and keeps its 40%
low-battery threshold. No stale green dial, invented zero or old source is used.
Controller/transport tests use fake streams; the opt-in hardware fixture is
`desktop/tests/battery-relay-live_test.qml`.

Google Health is a later, separate milestone: authorize only
`googlehealth.settings.readonly`, confirm the actual Fitbit Air response, keep
its source last-sync timestamp, and disclose its Internet/freshness dependency.
The documented pairedDevices resource does not supply explicit Fitbit charging
state; unknown must remain unknown. Never store Google tokens in the repository,
Nix configuration or BLE advertisements.
