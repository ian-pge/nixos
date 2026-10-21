# BLE — Battery Relay 0.6.0

Android app **BLE**, application ID **`dev.ian.ble`**. Both PC battery readers now
use **passive BLE advertisement monitoring**. Phone and Fitbit share one
non-connectable announcement; Pixel Buds are read directly from their own BATT
announcements. No GATT connection, pairing or continuous active scan is used
for battery reception.

No root, Shizuku, KDE Connect, Android Studio, hosted relay or Play Store
publication is required. Phone data is local; Fitbit uses Google Health with
the owner's existing authorization. Production signing is not set up.

## Components

- `android/`: Kotlin application and standard foreground connectedDevice service.
  Battery changes update a non-connectable/non-scannable legacy advertisement.
  Android's controller repeats it approximately once a second, without an app
  heartbeat timer or wake lock. No PC address setup.
- `receiver/`: two Rust executables sharing `observer.rs`, the BlueZ
  AdvertisementMonitor lifecycle. One instance per source serves all screens.
- [PROTOCOL.md](PROTOCOL.md): v2 packet, source dates, passive presence semantics
  and independent Fast Pair output.
- [receiver/README.md](receiver/README.md): build, operation and live checks.

Android **0.6.1** uses the same v2 protocol as receiver **0.6.0**. Both sides must
support passive advertisements (0.6.0 or newer). The old GATT transport
and connection/battery JSON events are removed, not kept as fallbacks.
The existing public UUID, Google authorization, signature and auto-start
preference survive an in-place update. The obsolete PC-address preference was
removed by 0.6.0. The UI says **Diffusion active**, not “connected to PC”:
announcements have no receipt acknowledgement.

### Pixel Buds : lecture directe Fast Pair

Le PC lit maintenant les annonces chiffrées **Battery All The Time (BATT)**,
indépendamment du téléphone, de l’application BLE et d’une connexion audio.
La lecture du boîtier fermé a été validée sur le matériel réel.

La procédure complète est dans **[pairing/README.md](pairing/README.md)** :
analyse de Google Play Services, format des annonces, clés, appairage PC,
déchiffrement, résultats, erreurs rencontrées et commandes pour reproduire
l’installation. Ne pas refaire l’appairage si la clé existe.

- `battery-relay-receiver` : téléphone/Fitbit, via les annonces non connectables de l’application.
- `fast-pair-battery` : boîtier/gauche/droite, par observation des annonces BLE.
  Depuis le récepteur 0.5.0, il utilise AdvertisementMonitor en mode passif,
  sans StartDiscovery permanent. Il ne se connecte pas aux écouteurs et ne
  provisionne aucune clé.
- `pairing/` : helper manuel d’appairage, jamais lancé par la barre.
- Clé privée : `~/.local/state/battery-relay/pixel-buds.account-key`, mode
  `0600`, dossier `0700`, persisté par la configuration NixOS. La configuration
  ne contient que son chemin, jamais sa valeur.
- La barre affiche le pourcentage du boîtier ; l’infobulle contient les trois
  niveaux. Un élément sous 20 % rend le cadran rouge. Pas de repli vers la
  batterie Bluetooth globale, l’ancien lecteur RFCOMM ou une valeur mémorisée.
- Les sources téléphone/Fitbit et écouteurs ont des processus et des fraîcheurs
  indépendants, chacun partagé par tous les écrans.

Android **0.5.0** a retiré l’adaptateur Google Widget, sa carte, sa permission
et sa caractéristique GATT, puis libéré uniquement le host 4421 de BLE et ses
préférences. Après cette migration, **0.6.1** retire aussi son code de nettoyage,
ses appels et son test dédié, ainsi que le nettoyage de l’ancienne adresse PC.
Les tests d’absence des permissions inutiles restent dans la suite actuelle.
Les réglages du relais, l’autorisation Google et le Fitbit sont conservés.

Le packaging `packages/battery-relay.nix` ne prend que les sources Rust.
Les clés et signatures Android restent hors du Nix store et du dépôt.
Inspecter la barre réelle avec `qs ipc -c top-bar call topbar batteryStatus` :
la source des écouteurs doit être `fast-pair`.

Le moniteur passif nécessite `hardware.bluetooth.settings.General.Experimental = true`
sur BlueZ 5.87, déclaré dans `system/bluetooth.nix`. Cela expose l'API D-Bus ;
`KernelExperimental` reste désactivé. L'ancien scan actif a été retiré après
avoir isolé son interférence avec la reconnexion de la MX Anywhere 3S : deux
cycles arrêt/allumage réussissaient avec le lecteur des écouteurs seul désactivé,
alors que la barre et le relais téléphone/Fitbit continuaient à fonctionner.
Le déchiffrement et la clé d'appairage ne changent pas.
Le profil expérimental de mesure de distance RAP est explicitement exclu avec
`disabledPlugins = ["rap"]` : il n'est pas nécessaire aux moniteurs. Son exclusion
seule n’avait pas corrigé l’ancien relais GATT ; le relais 0.6.0 ne se connecte plus.
Après un changement de ces options, faire
le rebuild puis `sudo systemctl restart bluetooth` ; NixOS conserve sinon le
daemon en cours pour éviter de déconnecter automatiquement clavier/souris.

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
3. Activate the relay from the dashboard; no PC address or pairing is needed.
   Copy the public installation identifier from Settings; start the receiver
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
an app update, using the saved installation identifier. The
standard `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` receiver starts the existing
`connectedDevice` foreground service; no pairing, wake lock, alarm or battery
optimization exemption is added. If Bluetooth is off, the service waits for it.
The app's Stop button disables this automatic resume too (as does the notification's
Stop action on Android 12). Missing Bluetooth permissions prevent resume. Android
force-stop or restricted battery settings can prevent delivery; reopen and
activate the app in that case. No restart loop bypasses these system decisions.

On Android 13+ (including this Pixel), BLE neither declares nor requests
`POST_NOTIFICATIONS`, so the relay runs without a notification in the drawer.
The required foreground-service notification is still supplied to Android:
the system's Active apps list remains available to inspect or stop the service.
Android 12 still displays the foreground notification. This is standard platform
behavior, not a hidden-service workaround; background operation and boot resume
use the same foreground service.

## Privacy

Current mode is deliberately **unencrypted and unpaired**, as explicitly chosen
by the owner after the encrypted prototype failed. The public installation ID
is not authentication. Nearby devices can observe,
track or imitate the exchange; only battery telemetry belongs on this service.

## Fitbit / Google Health: owner setup

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
`lastSyncTime` is retained end-to-end, floored to one-second wire precision. Readings older than **6 hours** are marked
old in the app and hidden on the PC. Repeated BLE advertisements do not renew that
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

## Validation of the passive replacement

Cleanup follow-up (Android 0.6.1): the completed migration class, its dedicated
test and old-widget fixture setup are removed. Permission guards now live with
the current application tests. The receiver no longer enables Tokio `test-util`.
Both QML readers stop on exit 78 and resume after reconfiguration; temporary
runtime errors still retry. Validation: 44 Android tests, lint/APK build, 26 Rust
tests, Clippy, phone QML (15), earbud QML (11), feature controllers (37), static
wiring checks and Nix builds passed. Android 0.6.1 (versionCode 14) was installed
in place on 2026-10-21 at 13:17. Before installation, the retired widget host,
widget preferences and PC-address setting were confirmed absent. The app resumed
advertising automatically through MY_PACKAGE_REPLACED; the actual bar received
fresh phone data and the Fitbit reading, with passive monitoring and discovery
off. No application data, Google authorization or installation UUID was reset.

See [receiver validation](receiver/README.md#actual-bar-checks). Android unit/UI
tests, lint, Rust decoding/lifecycle tests, static wiring and QML battery
controllers are tested separately from the real devices. The full desktop
composition suite also covers unrelated ongoing layout changes.

The APK was installed in place on 2026-10-21, resumed automatically after the
update and delivered both sources with the screen dozing. Earbud provisioning
and all existing Bluetooth pairings were unchanged. Long-term power draw,
deep idle without USB and actual reboot/distance reliability require physical
testing; no measured autonomy claim is made.
