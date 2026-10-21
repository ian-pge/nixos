# Battery Relay v2 — passive advertisements

Android BLE 0.6.0 and receiver 0.6.0 replace the connected GATT transport.
There is no v1 fallback, characteristic, CCCD, subscription, peer-address filter,
pairing agent, connection recovery or active discovery in the runtime readers.

The phone broadcasts non-connectable, non-scannable **legacy** BLE advertisements
at Android's INTERVAL_HIGH (1600 × 0.625 ms ≈ 1 second), TX_POWER_LOW. This is
ordinary repeated advertising, not the separate BLE Periodic Advertising feature.
The Bluetooth controller repeats the data; the app has no heartbeat timer.
Android's AdvertisingSet API updates the data in place when battery/cloud state
changes. API writes are serialized/coalesced and confirmed asynchronously.
An Android success callback proves radio configuration, **not PC reception**.

## Identification and size

One Service Data AD structure (type 0x21):
length/type (2 bytes), installation UUID (16 bytes, little-endian on air), payload
(12 bytes). Total: **30 bytes**, within the 31-byte legacy limit. No device name,
TxPower AD, separate UUID list or scan-response data is included. Android omits
the Flags AD for these non-connectable advertisements.

The existing random public installation UUID is retained across upgrades.
The PC selects that exact ServiceData UUID, never a MAC or display name.
The UUID is not a secret; nearby devices can observe, track or impersonate these
unencrypted announcements. Never put Google credentials or control commands here.

## Payload

Multi-byte integers are big-endian. Dates are unsigned Unix **seconds**, converted
to milliseconds in the PC JSON output. Precision is one second, valid through
2106; milliseconds are floored, not rounded forward.

| Offset | Bytes | Value |
| --- | --- | --- |
| 0 | 1 | Version 2 |
| 1 | 1 | Phone percentage 0–100, or 255 unknown |
| 2 | 1 | Phone charge flags |
| 3 | 1 | Fitbit percentage 0–100, or 255 absent/unknown |
| 4 | 4 | Phone battery observation date, nonzero |
| 8 | 4 | Fitbit's original Google lastSyncTime; 0 iff absent |

Flags: bit 0 = plugged state known, bit 1 = plugged, bit 2 = charging state known,
bit 3 = charging. All other bits zero. A true value without its known bit is invalid.
Full/plugged/not charging are separate. Fitbit does not provide charging information.

Phone source time changes only on a meaningful battery update or a fresh Android
battery observation after process start. Repeating the radio payload or refreshing
Fitbit must not change it. Fitbit's date is never replaced by a fetch/report date.
The PC hides Fitbit after six hours without source sync, even if Android's cloud
timer is delayed. Revocation/absence is an explicit percent=255/date=0, in the same
atomic packet as the phone, not a separate one-shot withdrawal.

Shared Android/Rust vector:
phone 73%, plugged but not charging, phone date 1700000000000 ms;
Fitbit 42%, sync date 1699999100000 ms:
`02 49 07 2a 65 53 f1 00 65 53 ed 7c`.

## Passive receiver and UI output

Both executables use the same `observer.rs` transport:
BlueZ AdvertisementMonitor, no StartDiscovery or GATT operations. A raw
UUID+version prefilter and a payload-version prefilter handle hardware and
BlueZ 5.87 software matching respectively (its software matcher strips UUIDs).
Exact ServiceData UUID selection and strict v2 decoding follow this coarse filter.

A live DeviceFound establishes presence before any cached property can be used.
DeviceLost removes that address (requested absence timeout: 180 seconds).
Advertising-address rotation does not invalidate a newer present address.
Malformed matching payloads are rejected; unknown values are never zero.
Adapter-off/removal, daemon replacement, monitor release, output failure and
process exit invalidate data. After a suspended observation loop of ≥180 seconds,
a new monitor must establish presence again.

One atomic NDJSON event supplies both sources:

```json
{"event":"relay","mode":"passive","available":true,"phone":{"percent":73,"pluggedIn":true,"charging":false,"updatedAt":1700000000000},"fitbit":{"percent":42,"updatedAt":1699999100000},"observedAt":1700000001234,"receivedAt":1700000001234}
{"event":"relay","mode":"passive","available":false,"phone":null,"fitbit":null,"observedAt":null,"receivedAt":1700000002000}
```

`fitbit:null` withdraws Fitbit while retaining a present phone. `observedAt` is the
last matching content/DeviceFound observation on the PC. `receivedAt` is when the
helper reports its monitor state to the UI, every 30 seconds or on value changes.
Those status reports do not invent new radio observations or source timestamps.
An unchanged battery remains visible while the monitor still reports presence.
The UI expires a silent/dead helper after 180 seconds and hides data immediately
on EOF or explicit unavailable. The existing UI property `connected` now means
valid passive presence, **not an ACL/GATT link**. It accepts only `relay/passive`
events; the old `connection`/`battery` event sequence is removed.

## Sortie indépendante Fast Pair

Les écouteurs sont indépendants du téléphone. L’ancien lecteur Google Widget
et son transport ont été retirés.
Le lecteur `fast-pair-battery` observe directement les annonces BATT, avec la clé
privée propre au PC. Voir [le protocole et l’appairage](pairing/README.md).

Sa sortie NDJSON est indépendante :

```json
{"event":"earbuds","mode":"passive","available":true,"case":{"percent":85,"charging":false},"left":{"percent":73,"charging":false},"right":{"percent":19,"charging":true},"observedAt":1700000000000,"receivedAt":1700000000123}
{"event":"earbuds","mode":"passive","available":false,"case":{"percent":null,"charging":null},"left":{"percent":null,"charging":null},"right":{"percent":null,"charging":null},"observedAt":null,"receivedAt":1700000001000}
```

`observedAt` est la dernière observation BlueZ correspondante sur le PC, pas une
date fournie par l’accessoire. `receivedAt` date l’émission de cet état vers la vue.
Aucune mesure n’est persistée. Depuis le récepteur 0.5.0, `mode: "passive"`
est obligatoire : BlueZ AdvertisementMonitor établit la présence avec DeviceFound
et la retire avec DeviceLost (délai d'absence demandé : 180 secondes). Les sources
boîtier/écouteurs sont suivies indépendamment ; une adresse perdue ne retire pas
une autre source encore présente. Les propriétés en cache sans DeviceFound ne
peuvent pas créer une présence.

Le lecteur rapporte cet état toutes les 30 secondes même si les valeurs n'ont
pas changé : `receivedAt` avance, **pas `observedAt`**. Ce rapport ne prétend pas
être une nouvelle mesure radio. BlueZ peut dédupliquer les valeurs ServiceData
tout en surveillant la présence ; attendre une variation de pourcentage serait
incorrect. La vue expire un lecteur silencieux après 180 secondes. Le lecteur
recrée sa session après une suspension de sa boucle supérieure au délai de perte
du moniteur, pour ne pas réaffirmer une ancienne présence au réveil.

EOF, libération du moniteur, arrêt du Bluetooth ou remplacement de bluetoothd
masquent cette source sans affecter téléphone/Fitbit. Aucun StartDiscovery,
scan périodique ou repli vers l'ancien lecteur actif n'est utilisé.

La sortie n’inclut ni Account Key, ni adresse Bluetooth ni contenu radio brut.
La barre ne lit jamais le fichier de clé ; seul le processus Rust l’ouvre.
