# Battery Relay v1

This is a data-only Bluetooth Low Energy GATT service. It does not register,
connect or modify A2DP/HFP profiles. The phone is the peripheral/GATT
server; the PC is the central/client. Existing Bluetooth audio
pairings are separate and must be tested independently on the phone.

Service UUID: a random **public installation identifier**, generated once and
stored in the Android app's preferences. The PC selects it with `--service UUID`.
It remains stable when the phone rotates its BLE address; it is not a secret.
Battery characteristic UUID: `d973f2e0-b19e-4f19-9a67-6c414c65f802`.

The characteristic supports **read + indications**, with an ordinary read/write
CCCD. No link encryption, native pairing, bond or trust flag is required. This is
an explicit owner-approved privacy/security tradeoff, not a fallback on error.
The Android app filters requests by the configured PC address; that address and
the public service identifier can be observed/spoofed and are not authentication.
Nearby devices may intercept or impersonate this exchange. Do not use it for
credentials, commands or sensitive account data. An advertisement contains only
the public service UUID, never a battery value or device name. The stable UUID
can itself allow tracking by nearby observers.

## Wire format

Each read/indication contains exactly 12 bytes; all multibyte numbers are big-endian.
It fits the default 20-byte ATT payload without depending on MTU negotiation.

| Offset | Size | Meaning |
| --- | --- | --- |
| 0 | 1 | Protocol version: `1` |
| 1 | 1 | Device kind: `1` phone, `2` Fitbit |
| 2 | 1 | Percentage: `0`–`100`; `255` means unknown |
| 3 | 1 | Flags below |
| 4 | 8 | Source timestamp: positive Unix milliseconds, at most 2^53−1 |

Flags: bit 0 = plugged state known; bit 1 = plugged; bit 2 = charging state
known; bit 3 = charging. Bits 4–7 are reserved and must be zero. A true plugged
or charging bit without its corresponding known bit is invalid. The source must
not infer plugged/charging from a percentage of 100. A full battery may still
be plugged in without actively charging.

Reject malformed lengths, unsupported versions/kinds, percentages outside the
defined range, invalid flags and invalid timestamps. Do not turn missing data
into zero or false. The Android sender serializes indications and coalesces
battery changes. ATT confirms delivery to the PC's Bluetooth stack, not output
to the final widget. The receiver separately emits successfully parsed values.

Shared test vector: phone at 73%, plugged in but not charging, source timestamp
1700000000000 = `01 01 49 07 00 00 01 8b cf e5 68 00`.

## Freshness and reconnection

Send a current phone snapshot after connection and after meaningful battery
changes. While connected, send a liveness snapshot every 60 seconds as scheduling
allows, without a wake lock or exact alarm. Receiver-side phone liveness expires
after 180 seconds without a phone snapshot. Device disconnection, blocking or
adapter shutdown invalidates the session immediately. BlueZ's generic Connected
property alone is insufficient because another Bluetooth profile may keep it true.
Screen-off scheduling and reconnection must be validated on the actual Pixel.

The source timestamp is not the packet reception time. Google Health's Fitbit
reading preserves `lastSyncTime`; forwarding it again never creates a new
measurement. A Fitbit packet cannot start or keep the phone session alive.
The Android sender prioritizes phone snapshots and shares a single outstanding
indication slot between both sources. Reads still return the current phone.

Version 0.2 of the applications implements kind 2. Fitbit packets are sent only
after this optional provider has supplied data; no fake device is advertised.
Fitbit's power fields are always unknown because the API does not supply them.
When its consent is removed, device disappears or last sync is too old, a kind-2
packet with percentage 255 and flags 0 withdraws the previous Fitbit reading.
Its timestamp is the withdrawal time, **not** a fresh battery measurement.
Consumers hide that source. A connection/EOF loss clears both sources.

The receiver must be updated to 0.2 before enabling the optional Fitbit provider;
the earlier phone-only receiver rejected kind 2. The wire layout remains v1.
PC consumers independently enforce a 6-hour Fitbit source-age limit and the
180-second phone/session liveness limit. The app fetches Google every 15 minutes
while enabled; BLE heartbeats can carry the same cloud timestamp in between.

## Receiver output

Stdout is newline-delimited JSON; diagnostics go to stderr.

```json
{"event":"connection","connected":true}
{"event":"battery","device":"phone","percent":73,"pluggedIn":true,"charging":false,"updatedAt":1700000000000,"receivedAt":1700000000123}
{"event":"battery","device":"fitbit","percent":42,"pluggedIn":null,"charging":null,"updatedAt":1699999100000,"receivedAt":1700000000124}
{"event":"connection","connected":false}
```

Unknown percentages and power states are JSON null. A consumer must invalidate
live readings on a disconnected event or receiver exit, without silently falling
back to a cached or coarse native Bluetooth percentage.

## Sortie indépendante Fast Pair

Depuis Android 0.5.0 / récepteur 0.4, les écouteurs ne font plus partie du service
GATT du téléphone. La caractéristique expérimentale du widget Google a été retirée.
Le lecteur `fast-pair-battery` observe directement les annonces BATT, avec la clé
privée propre au PC. Voir [le protocole et l’appairage](pairing/README.md).

Sa sortie NDJSON est indépendante :

```json
{"event":"earbuds","available":true,"case":{"percent":85,"charging":false},"left":{"percent":73,"charging":false},"right":{"percent":19,"charging":true},"observedAt":1700000000000,"receivedAt":1700000000123}
{"event":"earbuds","available":false,"case":{"percent":null,"charging":null},"left":{"percent":null,"charging":null},"right":{"percent":null,"charging":null},"observedAt":null,"receivedAt":1700000001000}
```

`observedAt` est la dernière observation BlueZ correspondante sur le PC, pas une
date fournie par l’accessoire. `receivedAt` date l’émission de cet état vers la vue.
Aucune mesure n’est persistée. Les rapports du boîtier et des écouteurs en usage
expirent séparément après 180 secondes, suspension comprise. Des observations
identiques rafraîchissent la présence ; une variation de pourcentage n’est pas
nécessaire. EOF, erreur, arrêt du Bluetooth ou du processus masquent cette source,
sans affecter téléphone/Fitbit.

La sortie n’inclut ni Account Key, ni adresse Bluetooth ni contenu radio brut.
La barre ne lit jamais le fichier de clé ; seul le processus Rust l’ouvre.
