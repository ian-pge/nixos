# Battery Relay

The Android app is named **BLE**, with application ID **`dev.ian.ble`**.
The PC helper and wire protocol retain their Battery Relay names and UUIDs.

Local application for sending the Pixel's battery to this PC over a
dedicated Bluetooth Low Energy data service, independently of audio profiles.
No root, Android Studio, hosted relay, KDE Connect or Play Store publication is
required. The phone's battery remains fully local. Version 0.2 adds an optional
Fitbit provider via Google Health, requiring Internet and explicit Google OAuth
consent. The owner has now connected Google successfully; long-term Fitbit
freshness and accuracy still need device-level validation. Production Android
signing is not set up.

## Components

- `android/`: Kotlin app, battery change receiver and foreground `connectedDevice`
  service. It exposes a BLE GATT server, with low-power advertising while waiting
  for the PC and indications while subscribed. No scanning or wake lock.
  The native Macchiato UI separates the dashboard from settings. Google Identity
  Services manages optional account authorization; only settings/device metadata
  is requested, never activity, sleep or heart-rate data.
- `receiver/`: Rust BLE central using BlueZ D-Bus. It finds the explicitly selected
  public installation UUID, subscribes and emits NDJSON for Quickshell.
  No pairing agent, bond/trust changes, adapter-power or audio-profile commands.
- [PROTOCOL.md](PROTOCOL.md): phone/Fitbit 12-byte frames and the independent Fast Pair output,
  with shared Android/Rust test vectors.

### Pixel Buds : lecture directe Fast Pair

Le PC lit maintenant les annonces chiffrées **Battery All The Time (BATT)**,
indépendamment du téléphone, de l’application BLE et d’une connexion audio.
La lecture du boîtier fermé a été validée sur le matériel réel.

La procédure complète est dans **[pairing/README.md](pairing/README.md)** :
analyse de Google Play Services, format des annonces, clés, appairage PC,
déchiffrement, résultats, erreurs rencontrées et commandes pour reproduire
l’installation. Ne pas refaire l’appairage si la clé existe.

- `battery-relay-receiver` : téléphone/Fitbit, via le service BLE de l’application.
- `fast-pair-battery` : boîtier/gauche/droite, par observation des annonces BLE.
  Il ne se connecte pas aux écouteurs et ne provisionne aucune clé.
- `pairing/` : helper manuel d’appairage, jamais lancé par la barre.
- Clé privée : `~/.local/state/battery-relay/pixel-buds.account-key`, mode
  `0600`, dossier `0700`, persisté par la configuration NixOS. La configuration
  ne contient que son chemin, jamais sa valeur.
- La barre affiche le pourcentage du boîtier ; l’infobulle contient les trois
  niveaux. Un élément sous 20 % rend le cadran rouge. Pas de repli vers la
  batterie Bluetooth globale, l’ancien lecteur RFCOMM ou une valeur mémorisée.
- Les sources téléphone/Fitbit et écouteurs ont des processus et des fraîcheurs
  indépendants, chacun partagé par tous les écrans.

Android **0.5.0** retire l’ancien adaptateur Google Widget, sa carte, sa permission
et sa caractéristique GATT. Une migration libère uniquement le host 4421 de BLE
et ses préférences. Les réglages du relais, l’autorisation Google et le Fitbit
sont conservés. L’ancienne technique savait parfois lire les trois lignes,
mais Google les retirait en arrière-plan : elle n’est plus une source active.

Le packaging `packages/battery-relay.nix` ne prend que les sources Rust.
Les clés et signatures Android restent hors du Nix store et du dépôt.
Inspecter la barre réelle avec `qs ipc -c top-bar call topbar batteryStatus` :
la source des écouteurs doit être `fast-pair`.

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
Robolectric UI tests use an explicit, checksum-pinned Android 15 runtime and
offline resolution, not an implicit Maven download at test time. They render
native layouts to `android/app/build/reports/ui/`; these are **fictitious test
fixtures**, not evidence of a real Google account connection. The test runtime
is never included in the APK.
The
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
3. In Settings, configure this PC's Bluetooth address and activate the relay
   from the dashboard. Copy the public installation identifier from Settings; start the receiver
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
The app's Stop button disables this automatic resume too (as does the notification's
Stop action on Android 12). Missing Bluetooth permissions/configuration prevent resume. Android
force-stop or restricted battery settings can prevent delivery; reopen and
activate the app in that case. No restart loop bypasses these system decisions.

On Android 13+ (including this Pixel), BLE neither declares nor requests
`POST_NOTIFICATIONS`, so the relay runs without a notification in the drawer.
The required foreground-service notification is still supplied to Android:
the system's Active apps list remains available to inspect or stop the service.
Android 12 still displays the foreground notification. This is standard platform
behavior, not a hidden-service workaround; background operation and boot resume
use the same foreground service.

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
Doze behavior and power consumption still need long-term testing.

Autostart update, 2026-10-20: JVM tests, lint and APK build passed; installing the
update on the Pixel resumed the opted-in foreground relay through
`MY_PACKAGE_REPLACED`, without opening its activity. Pressing Stop persisted
`enabled=false`; another APK update then logged a skipped resume and left the
service stopped. The relay was then reactivated through its button; the PC's
existing receiver resubscribed and received 99%, plugged and charging. The same
startup receiver is registered for `BOOT_COMPLETED`. A subsequent owner-triggered
phone reboot did resume the foreground service automatically (`RESUME` observed
over ADB); the owner confirmed the PC widget reappeared without manual activation.
Reconnection was not immediate; no precise latency guarantee has been established.

`desktop/features/power/BatteryRelayData.qml` consumes the receiver's NDJSON.
EOF, disconnect, malformed data and expired heartbeats clear the reading. The
phone dial follows the existing accessory visibility policy and keeps its 40%
low-battery threshold. No stale green dial, invented zero or old source is used.
Controller/transport tests use fake streams; the opt-in hardware fixture is
`desktop/tests/battery-relay-live_test.qml`.

## Fitbit / Google Health: owner setup

First rebuild the PC configuration normally so it runs receiver **0.2** and the
new Fitbit-aware widget, **before enabling Fitbit in the phone app**. Receiver
0.1 deliberately rejected the previously reserved Fitbit packet kind. The new
Android app sends only phone packets while Fitbit has never been configured, so
installing its UI update alone does not interrupt the existing phone provider.

This integration uses the official [Google Health API](https://developers.google.com/health/setup)
and Android's [AuthorizationClient](https://developer.android.com/identity/authorization).
There is no hosted backend, embedded browser, API key, client secret or refresh
token to paste into the app. Google Play services obtains short-lived access
tokens on demand; the app never saves or logs them, and never sends them over BLE.

One-time configuration in your own Google Cloud project:

1. Create/select a personal development project and enable **Google Health API**
   (`health.googleapis.com`). Do not enable billing or unrelated APIs as part
   of this setup.
2. Configure Google Auth Platform's consent screen (app name **BLE**).
   Use External / Testing and add the Google account used in Google Health to
   the **test users**. Use your own real contact details, not placeholders.
3. Under Data Access, add **only**
   `https://www.googleapis.com/auth/googlehealth.settings.readonly`.
4. Create an OAuth client of type **Android**, package `dev.ian.ble`.
   This development APK's public signing SHA-1 is
   `37:6D:9B:67:D2:22:F1:2D:B9:F2:C7:A8:8B:3B:5D:42:EE:80:54:55`.
   The current values can also be copied from **Settings → Accès Google** in
   the app. Do not upload or share the private signing keystore. No web client
   or server secret is needed for this on-device-only authorization flow.
5. Sync the Fitbit Air in Google Health using that same Google account.
6. In BLE, tap **Associer mon Fitbit**, read the disclosure and accept
   Google's authorization yourself. If several trackers are available, select
   the intended one. The app never auto-accepts consent or launches it at boot.

The linked-account identity check and `users/me/pairedDevices` requests use HTTPS
and read-only settings access. Pagination is bounded; a disappeared selected
tracker never silently becomes another device. No cached response, unknown
percentage or `batteryStatus: High` is converted into a made-up percentage.

Refresh policy: one cloud fetch on authorization/start, then every **15 minutes**
while the relay is active (best effort under Android scheduling), plus explicit
manual refresh. Google only exposes the last synchronization with its own app;
this is not a continuous, direct Bluetooth battery feed from the Fitbit. Source
`lastSyncTime` is retained end-to-end. Readings older than **6 hours** are marked
old in the app and hidden on the PC. Repeated BLE heartbeats do not renew that
age. The API does not provide an explicit charging state, so both power fields
remain null even at 100%.

Disconnecting Fitbit removes this integration's local selection/data, stops
polling, withdraws the PC measurement and requests revocation of the Google grant.
If revocation fails, the app says so; it must then be retried or removed from
the Google account's third-party access page. The phone's local relay remains
independent of Google consent, connectivity and API errors.

The owner has completed the Google setup and reported a working connection;
the renamed app's SDK log also confirms the requested settings scope was granted.
Long-term Fitbit freshness/accuracy still needs real-device validation. Local
tests exercise synthetic API responses and BLE/QML delivery; they do not prove
every field or metric will be present on this account.

## 0.2 verification (2026-10-20)

- 33 Android JVM tests pass, including native-rendered UI fixtures at normal and
  large text sizes, Google SDK cancellation/revocation races, API pagination,
  malformed/unknown values, retained sync time and the shared indication queue.
- Offline APK build and lint pass (0 errors; dependency/style warnings remain).
- Rust: 17 tests, Clippy with warnings denied, and formatting pass.
- Quickshell: 15 relay-data tests, 32 feature-controller tests, wiring checks and
  the isolated real desktop/Bar composition suite pass, including the Fitbit dial.
- Receiver 0.2 and the desktop package build with Nix, without activating the
  desktop configuration. The live bar is deliberately left on its installed
  receiver until the owner's normal rebuild.
- APK 0.2 was installed over the existing app with the same key; permissions,
  PC address, installation UUID and enabled preference were retained. Android
  resumed the service after replacement and the PC resubscribed successfully.
- An opt-in hardware test with the packaged 0.2 receiver and real power
  controller received the phone at 100%, plugged in and not actively charging,
  then verified invalidation on stopping its source. Its temporary helper
  exited; the original bar-owned receiver was left running. The updated activity
  also launched successfully on the Pixel without unlocking it.

No real Google grant, Fitbit reading, health data or OAuth credential was used
by these tests. No phone unlock, reboot, audio change or Bluetooth re-pairing
was performed for this update.

### 0.2.1 authorization diagnostics

The initial activity callback incorrectly discarded Google's result Intent
unless Android reported `RESULT_OK`, hiding SDK errors behind a generic
"authorization cancelled" message. It now passes every supplied result to
`AuthorizationClient.getAuthorizationResultFromIntent`, as in the official
Android flow. Missing results and IntentSender launch failures have separate
messages; a cancelled activity is never treated as proof of a voluntary cancel.
Successful authorization still requires the SDK result, the exact requested
scope and a nonempty access token. No consent check is bypassed.

The authorization log (`BLEAuth` in the renamed app) records only numeric result/status codes, booleans and bounded
error categories, never account details, Intent extras, tokens or raw exception
messages. Regression tests cover cancelled results containing a real SDK error,
empty results, SDK cancellation/network failures, invalid replies and launch
failure. A new owner-driven attempt is needed to identify the actual Google
failure on this account; correcting diagnostics alone is not an OAuth success.
The 0.2.1 APK passed 39 Android tests, lint and offline assembly and was installed
over 0.2.0. The phone relay resumed and the PC resubscribed; no Google consent
or Cloud configuration was changed by the update.

### 0.3 Android identity: BLE

The owner registered the Google Android client as `dev.ian.ble` and chose the
display name **BLE**. Android's application ID, Kotlin/resource namespace,
component/action names and visible app/notification names now match that choice.
The signing key is unchanged, so the SHA-1 above still applies. The PC protocol,
characteristic UUID and public installation UUID are independent of this rename.

Android treats this as a new application, not an in-place package rename.
Migration copies only the relay preferences (PC address, installation UUID and
enabled preference) into the new private app storage before its first launch.
Google data and Android permissions are not copied. Grant Nearby Devices to
**BLE**, then activate the relay (0.3.3 no longer asks for notifications). Stop the old app before the
new one starts advertising; remove it only after real reception from BLE is
verified. This is a one-time developer-assisted migration, not a legacy provider
or a compatibility layer built into the application.

### 0.3.1 launcher identity

BLE now has an original two-tone B monogram (Macchiato yellow/mauve on a dark
background), used by the adaptive launcher icon and the app header. A separate
monochrome layer supports Android themed icons; the notification keeps its
purpose-built white battery glyph. Vector assets remain sharp at all sizes and
the mark stays inside Android's 66dp safe circle. The app label comes from one
`app_name` resource. Package ID, signing key, Google scopes and BLE security are
unchanged. The 42 Android tests include label/launcher identity and native icon
rendering/mask checks; lint and the offline APK build pass.

Installed on the Pixel as 0.3.1. Both old and new applications were still running;
the old one was stopped, then the packaged PC receiver/power controller received
100%, plugged/not actively charging, from BLE alone. Only after this live check
was `dev.ian.batteryrelay` uninstalled. Its relay settings are retained in
`dev.ian.ble`; the one-time migration copy was removed. No Google authorization,
permissions, Bluetooth pairing or encryption setting was changed by this update.

### 0.3.2 computer icon

Replaced the B monogram with a simple desktop computer: a yellow screen frame
and mauve stand on the existing dark background. The app header and adaptive
launcher icon share the new design, including its monochrome themed variant.
The BLE name, notification battery glyph, relay settings and Google authorization
are unchanged. All 42 Android tests, lint (no errors) and the offline APK build
pass; the icon rendering test checks the screen opening, stand and safe circle.
Installed as an in-place update on the Pixel; version 0.3.2 and the resumed
foreground relay service were verified.

### 0.3.3 notification visibility

Removed the notification permission declaration and prompt; the mandatory
foreground-service notification is still supplied to Android. On the Pixel,
`POST_NOTIFICATION` is ignored while the foreground relay remains active.
The 44 Android tests, lint and APK build pass, including activation without
notification consent. Bluetooth and Google permissions/settings were preserved.

### Receiver 0.2.1 recovery validation

Observed a live failure where Android still had its battery GATT service and
PC subscriber, while BlueZ's connected device no longer exposed that service.
The former client did not recover. The receiver now bounds Bluetooth operations,
invalidates a removed service, releases only the selected private/unpaired LE
link when safe, and exits so Quickshell can start a fresh client. See the receiver
README for the exact safety checks. No stale percentage is kept as a substitute
for receiving data, and the 180-second expiry is unchanged.

On the Pixel, reinstalling the unchanged 0.3.3 APK during a live test removed
the GATT service. The new receiver detected it, released the selected LE link,
and Quickshell restarted the helper and received both sources automatically.
After that recovery, the controller stayed connected for 245 seconds, receiving
five distinct phone snapshots while the percentage stayed at 100%; Fitbit
remained available at 95%. The final Nix-packaged receiver also passed the live
read/invalidation smoke test. Notification suppression remained enabled.

Validation: 20 Rust tests, Clippy with warnings denied, 15 BatteryRelayData tests,
32 FeatureControllers tests, wiring checks, Wayland component compilation, and
both Nix package builds passed. Full DesktopComposition rendering was not run
in its required nested compositor. Long-term unplugged/Doze and real out-of-range
testing still remain; this test does not establish day-long reliability.
No NixOS/Home Manager activation was performed: the running bar still uses
receiver 0.2.0 until the owner's normal rebuild activates the new packages.
