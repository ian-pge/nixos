# Pixel Buds Pro 2 : appairage Fast Pair et lecture du boîtier fermé

Ce document conserve la procédure réellement utilisée le **20 octobre 2026**,
ses résultats, les erreurs rencontrées et les limites à respecter pour la refaire.
Le code d’appairage est dans ce dossier ; le décodeur utilisé en production est
dans [`../receiver/src/fast_pair.rs`](../receiver/src/fast_pair.rs).

**Ne pas refaire l’appairage si la clé existe.** Le lecteur de la barre réutilise
cette clé à chaque démarrage. Il ne se connecte pas aux écouteurs, ne les
réappaire pas et ne contacte pas Google.

## Résultat vérifié et architecture

Sur les Pixel Buds Pro 2 Porcelain de cette installation :

- appairage Fast Pair sécurisé depuis le PC, avec une clé propre au PC ;
- aucune réinitialisation, suppression de l’association existante, modification
  de firmware, opération Find Hub ou intervention dans les données privées Google ;
- après confirmation humaine que le couvercle était fermé : **9 observations
  BATT déchiffrées pendant une nouvelle capture de 25 secondes** ;
- boîtier, gauche et droite : **100 %** ; charge rapportée du boîtier `false`,
  des deux écouteurs `true` ;
- `bluetoothctl info` indiquait `Connected: no`, et aucune connexion aux
  écouteurs n’était listée par le contrôleur. Le scan BLE est sans connexion.

Cela valide la lecture dans cette situation, pas encore toutes les évolutions
de batterie, tous les firmwares, la consommation du scan ni tous les scénarios
de portée/suspension. Les bits « charging » sont ceux du périphérique, pas une
mesure du courant. En particulier, 100 % ne signifie pas « débranché ».

En production, `PowerController.qml` possède un seul `FastPairBatteryData` pour
tous les écrans. Celui-ci lance `fast-pair-battery`, séparément du récepteur
téléphone/Fitbit. Fermer BLE sur le téléphone ou perdre sa connexion ne doit pas
faire disparaître la batterie des écouteurs.

Depuis le récepteur **0.5.0**, le lecteur utilise le moniteur passif BlueZ,
pas une session StartDiscovery permanente. L'ancien scan a été retiré après
avoir reproduit une interférence avec la reconnexion de la souris. Le décodage
et l'appairage décrits ici restent identiques ; ne pas générer une autre clé.

Le cadran affiche uniquement le boîtier. Son infobulle contient les trois
pourcentages. Un élément strictement sous 20 % rend le cadran rouge, même si le
boîtier est plein ou en charge. Inconnu reste `null`/`—`, jamais zéro ni une
substitution par la batterie globale Bluetooth.

## 1. Pourquoi la lecture précédente ne suffisait pas

La batterie Bluetooth générique du PC ne fournissait pas le boîtier.
L’adaptateur Android `AppWidgetHost` pouvait lire le widget Batterie de Google,
mais Google retirait les lignes des accessoires en arrière-plan. Il ne constituait
donc pas une source continue indépendante. Ce lecteur, son écran, sa permission
et sa caractéristique GATT ont été retirés.

BLE Android 0.5.0 a conservé uniquement téléphone/Fitbit et supprimé
**le seul host 4421 appartenant à BLE** et ses préférences historiques,
sans toucher aux widgets d’autres applications, au compte Fitbit ou aux réglages
du téléphone. Cette migration étant terminée, son code et son test dédié ont été
retirés en 0.6.1. Aucun lecteur de widget ni chemin de secours ne subsiste.
Sur le téléphone de cette installation, l’ancien host et le fichier de
préférences ont été vérifiés absents après la mise à jour. L’ancienne autorisation
de liaison, encore listée par Android, a aussi été retirée uniquement pour BLE :

```sh
adb shell appwidget revokebind --package dev.ian.ble --user 0
```

Ce nettoyage ponctuel n’est ni une nouvelle autorisation ni une opération à
répéter au démarrage.

Une comparaison physique proche → salon → proche a identifié un candidat radio
avec des RSSI moyens d’environ −47 / −89 / −44,5 dBm. C’était une bonne attribution
expérimentale, mais pas une preuve cryptographique ni un décodage de batterie.

## 2. Découverte du format dans Google Play Services

La documentation publique de
[Battery Notification](https://developers.google.com/nearby/fast-pair/specifications/extensions/batterynotification)
décrit les types 3 et 4 contenant trois octets en clair. Ce n’était pas le format
des annonces du boîtier observées ici. Le projet
[OpenControlPixelBudsPro2](https://github.com/tedsluis/opencontrolpixelbudspro2/blob/main/PROTOCOL.md)
avait également relevé cette différence : ne pas prendre la spécification
générique pour une preuve de ce que ce firmware émet.

On a copié **les APK installés**, pas les bases privées, identifiants de compte
ou clés Google, avec les outils de développement déjà autorisés :

```sh
adb shell pm path com.google.android.gms
# Copier le base.apk désigné par la commande, dans un dossier privé temporaire.
adb pull CHEMIN_BASE_APK dossier-prive/gms-base.apk
nix shell nixpkgs#jadx --command jadx --help
```

Version étudiée : `com.google.android.gms` **26.40.32**, code `264032035`.
SHA-256 du base.apk :
`1bfbf0c0ddab74708e723d1fd9080dc16e8623b161973edcb08b257bddce42f0`.
Les APK et sources Google décompilées ne sont pas incorporés à ce dépôt.

La recherche de `decryptBatteryAllTheTimeData` dans les chaînes DEX a conduit
aux classes suivantes. Leurs noms obfusqués dépendent de la version :

| Classe/méthode observée | Rôle vérifié |
|---|---|
| `dzom.k` (`classes2.dex`) | Parsing des champs ; longueur multipliée par 4 pour les types 9/10 |
| `ebsc` | Identification BATT et choix afficher/masquer la notification |
| `ebot.e`, `gxqw` | Vérification du filtre d’Account Key et variantes 4/5/6 |
| `ebou.c`, `gxlp` | Dérivation de la clé avec `SASS-RRD-KEY` |
| `gxqu.a`, `gxge.a` | Masque AES et XOR des quatre octets |
| `dzob`, `ebnl`, `ebnj` | En-tête, composants, inconnus et charge |

Pour refaire l’analyse sur une autre version : repartir des chaînes et de leurs
références, puis vérifier les appels, les paramètres et les tailles. Ne pas se
fier au seul nom d’une fonction ni forcer un parseur pour obtenir un pourcentage
plausible.

Un service Google interne permet aussi de demander les batteries déjà décodées,
mais le chemin analysé comporte une liste d’applications autorisées. Le broadcast
de mise à jour cible les packages Google, pas toutes les applications.
Nous n’utilisons ni usurpation de package, ni permission privilégiée, ni root,
ni Shizuku, ni lecture de l’écran.

## 3. Format BATT et déchiffrement

Le service est `0000fe2c-0000-1000-8000-00805f9b34fb`.
Le décodeur actuel accepte uniquement la version **`0x10`** vérifiée ici.

Un exemple structurel est :

```text
10 | 40 [filtre de 4 octets] | 21 [sel de 2 octets] | 1a [4 octets chiffrés]
```

Pour les champs habituels, le quartet haut donne la longueur en octets.
Pour **les types 9 et 10**, il donne le **nombre de blocs de quatre octets** :
`0x1a` annonce quatre octets, `0x2a` huit, etc.

- type 9 : afficher la notification de batterie ;
- type 10 : masquer cette notification ;
- **`0x19` → `0x1a` n’est pas un changement d’état de charge** ;
- les types 0/2 contiennent le filtre d’association, le type 1 le sel ;
- le type 6 est le Random Resolvable Data facultatif.

### Vérifier à quelle clé correspond l’annonce

Pour les annonces BATT v1 prises en charge, construire :

```text
V = AccountKeyAvecPréfixe4Ou5Ou6
    || sel
    || éventuel(en-tête RRD || RRD)
    || en-tête BATT || contenu BATT chiffré
H = SHA256(V)
```

Découper `H` en huit entiers 32 bits **big-endian**. Pour chaque entier,
calculer le reste modulo le nombre de bits du filtre. Tous les bits
correspondants doivent être présents. Dans chaque octet du filtre, l’index 0
désigne le bit de poids faible. Le filtre lui-même ne doit pas être inversé.

Les variantes 4/5/6 ne servent qu’à cette correspondance. Le déchiffrement
utilise **l’Account Key originale** commençant par `0x04`.

### Décoder les quatre octets

```text
K = HKDF-SHA256(AccountKey, sel nul, info ASCII "SASS-RRD-KEY", 16 octets)
IV = sel de l’annonce (2 octets) || 14 octets nuls
masque = AES-128-Encrypt(K, IV)
clair[i] = chiffré[i] XOR masque[i], pour i = 0..3
```

AES/ECB/NoPadding sert ici à calculer **un bloc de masque**, comme pour le
premier bloc CTR ; il ne faut pas déchiffrer directement les quatre octets en ECB.

Le résultat attendu est `00 | gauche | droite | boîtier`.
Pour chaque valeur : `octet & 0x7f` donne le pourcentage, `octet & 0x80` la charge.
127 signifie inconnu ; le lecteur rejette les autres valeurs au-delà de 100.
Un boîtier `0xff` caractérise un rapport des écouteurs en usage, qui ne doit pas
effacer ni rafraîchir une mesure indépendante du boîtier.

Plusieurs blocs peuvent être présents. Le lecteur exige le filtre de clé,
l’en-tête nul et des valeurs valides, et refuse des résultats contradictoires.
Il ne teste pas des clés au hasard. Le filtre Bloom est probabiliste, **pas un
MAC cryptographique**, et ces annonces n’offrent pas de garantie anti-rejeu :
ce protocole sert à un indicateur de batterie, pas à une décision de sécurité.

## 4. Obtenir une clé PC par un appairage normal

Trois clés différentes interviennent :

1. La **clé publique du modèle**, non secrète, sert à authentifier l’échange.
2. Une clé de session AES dérivée d’un ECDH P-256 éphémère protège l’appairage.
3. Une **Account Key privée de 16 octets**, créée par notre PC, reste pour la lecture.

Ce n’est ni la clé Bluetooth interne de BlueZ ni une clé Find Hub ni un mot de
passe Google. Il ne faut pas extraire ou modifier ces autres secrets.

Modèle vérifié : **`c55c79` / `12934265`**, Pixel Buds Pro 2 **Porcelain**.
La clé publique est épinglée dans [`src/lib.rs`](src/lib.rs), provenant de
[cette entrée de métadonnées publiée](https://github.com/KULeuven-COSIC/WhisperPair/blob/main/toolkit-server/device-info.json).
**Seules ces métadonnées publiques ont été utilisées** : aucun code d’exploitation,
clé API, usurpation d’identité Google ou provisionnement de ce projet n’a été exécuté.
Une requête Google anonyme avait été refusée ; elle n’a pas été contournée.

La réponse cryptographique réelle des écouteurs a ensuite confirmé la clé
publique et leur adresse épinglée. Ne pas étendre ce test à d’autres périphériques
par nom ou proximité : pour un autre modèle, revérifier modèle, identité et clé.

### Procédure reproductible, uniquement si une nouvelle clé est nécessaire

Le chemin testé partait d’écouteurs déjà associés au Pixel et au PC en Bluetooth
classique. **Conserver l’association au téléphone et son propriétaire Find Hub.**
Le helper est volontairement limité au modèle et à l’identité validés dans
`src/lib.rs`. Il ne supprime aucune association et s’arrête s’il rencontre un
autre mode de réponse ou plusieurs composants à appairer.

1. Vérifier d’abord si la clé existe :

   ```sh
   fast-pair-battery --key-file "$HOME/.local/state/battery-relay/pixel-buds.account-key" --check
   ```

   Si elle est valide, **ne pas continuer l’appairage**. Une absence de batterie
   se diagnostique par le scan et les journaux, pas en recréant des clés.

2. Compiler le helper séparé, qui n’est jamais lancé par la barre :

   ```sh
   nix develop .#rust --command cargo test --locked --manifest-path tools/battery-relay/pairing/Cargo.toml
   nix develop .#rust --command cargo build --locked --manifest-path tools/battery-relay/pairing/Cargo.toml
   tools/battery-relay/pairing/target/debug/fastpair-setup check
   ```

   Créer le répertoire privé `~/.local/state/battery-relay` avec le mode `0700`
   s’il n’existe pas. `FAST_PAIR_ACCOUNT_KEY_FILE` peut désigner un autre
   **chemin absolu**, jamais contenir la clé. Ne pas écraser une ancienne clé.

3. Les deux écouteurs dans le boîtier ouvert, près du PC : appuyer brièvement sur
   le bouton arrière et **relâcher dès le clignotement blanc**. Ne pas maintenir
   le bouton pour une réinitialisation. Ne pas accepter un nouvel appairage sur
   le téléphone.

4. Observer l’annonce :

   ```sh
   tools/battery-relay/pairing/target/debug/fastpair-setup scan
   ```

   Le format moderne observé est `00 37 c5 5c 79 18 00`, pas simplement les
   trois octets du modèle. La capacité `00` signifie « pas de partage LE Audio
   annoncé et pas d’état usine », **pas** « appareil non appairable ».
   Voir [Provider Advertising](https://developers.google.com/nearby/fast-pair/specifications/service/provider).

5. Vérifier le transport avant toute écriture :

   ```sh
   bluetoothctl info 44:10:30:25:8F:4F
   hcitool con
   ```

   Sur BlueZ 5.87, `Connect` générique peut choisir le transport classique déjà
   associé, et `ConnectProfile` ne force pas le BLE. Ne pas utiliser ces commandes
   en supposant qu’elles n’ouvrent qu’un canal de données.

   Si aucune session BLE n’existe, le helper peut lire le service sur un canal
   ATT Linux natif (`L2CAP`, CID 4, adresse `LePublic`), sans root ni profil audio :

   ```sh
   tools/battery-relay/pairing/target/debug/fastpair-setup prepare-le
   ```

   Cette étape vérifie l’UUID du service et lit le Model ID ; aucun handle GATT
   n’est supposé constant. Elle laisse la liaison de diagnostic à BlueZ.
   Si une liaison existe déjà, vérifier qu’elle est bien la session **LE**
   de ce diagnostic, pas une session audio utilisateur. Ne pas ouvrir un second
   socket ATT concurrent : il peut échouer avec `Device or resource busy`.

6. Lancer explicitement une tentative sur cette session :

   ```sh
   tools/battery-relay/pairing/target/debug/fastpair-setup \
     pair-existing --owner-enabled-pairing --reuse-owned-le-session
   ```

   Le helper réussi utilise **les caractéristiques GATT gérées par BlueZ**,
   pas le socket de diagnostic. Il procède ainsi :

   - lit et vérifie le Model ID ; exige un MTU suffisant pour 80 octets ;
   - s’abonne aux notifications Key-based Pairing et Passkey ;
   - génère une paire P-256 éphémère ; `K = SHA256(ECDH)[0..16]` ;
   - écrit une demande chiffrée de type `0x00`, drapeaux `0x0c`
     (BLE et LE Audio), suivie de sa clé publique ;
   - exige une réponse chiffrée de type `0x02`, préférence LE, un composant
     primaire et **l’identité exacte attendue** ;
   - appelle `Device1.Pair` avec un agent propre à cette application, sans
     remplacer l’agent par défaut ;
   - à `RequestConfirmation`, transmet le code numérique chiffré de type `0x02`
     et exige le même code dans la réponse de type `0x03` avant confirmation ;
   - refuse Just Works, les autres périphériques et les confirmations aveugles ;
   - après succès du bond, crée une clé aléatoire commençant par `0x04` ;
   - sauvegarde et synchronise cette clé **avant** son unique écriture
     chiffrée dans la caractéristique Account Key ;
   - attend l’accusé d’écriture et ferme la session de diagnostic.

   Références :
   [procédure Fast Pair](https://developers.google.com/nearby/fast-pair/specifications/service/gatt),
   [caractéristiques](https://developers.google.com/nearby/fast-pair/specifications/characteristics),
   [extension BLE](https://developers.google.com/nearby/fast-pair/specifications/bledevice).

   Le protocole permet une écriture rétroactive après un appairage classique,
   mais seulement dans une fenêtre courte ; ce n’est **pas** le chemin utilisé
   ici. Ne pas supposer qu’une vieille association Bluetooth suffit à autoriser
   une écriture directe d’Account Key.

7. Fermer le boîtier et tester, sans relancer l’appairage :

   ```sh
   tools/battery-relay/receiver/target/debug/fast-pair-battery \
     --key-file "$HOME/.local/state/battery-relay/pixel-buds.account-key" --duration 30
   bluetoothctl info 44:10:30:25:8F:4F
   ```

   Vérifier les valeurs et l’absence de connexion active. Contrôler ensuite
   des changements réels et le fonctionnement habituel avec le téléphone.
   Ne pas considérer des valeurs de test ou une simple détection radio comme
   une preuve de lecture réelle.

### Arrêts sûrs et erreurs rencontrées

- `AlreadyExists`, timeout, mauvaise identité/code, MTU insuffisant ou réponse
  multi-composants : arrêter. Pas de suppression automatique de bond, reset ou
  changement des rôles audio.
- Un premier essai ATT natif a reçu une requête de lecture `0x08` des écouteurs
  pendant l’échange. ATT est bidirectionnel : ce n’était pas une réponse invalide
  au code numérique. L’appairage a été refusé, sans Account Key écrite.
  Le chemin final laisse **BlueZ gérer ATT et son serveur**, ce qui a résolu ce point.
- Après une écriture dont l’accusé est incertain, **conserver la clé sauvegardée**.
  Diagnostiquer avec elle ; ne pas générer une succession de clés, qui pourrait
  remplir la liste du périphérique et remplacer des clés moins récemment utilisées.
- Les premières étapes ont parfois conservé une session LE dans BlueZ après la
  sortie du socket de diagnostic. Inspecter cette session avant d’en créer une autre.
- L’outil refuse de générer une nouvelle clé quand le fichier existe.
  Aucun mode reset/flash/Find Hub n’est implémenté.

## 5. Stockage privé, persistance et barre

Clé active : `~/.local/state/battery-relay/pixel-buds.account-key`,
**16 octets bruts**, fichier `0600`, dossier `0700`.
Ne jamais l’afficher, la commiter, l’insérer dans un fichier Nix ou une commande,
ni la convertir en variable d’environnement contenant sa valeur.
Le lecteur refuse un fichier public, appartenant à un autre UID, un lien
symbolique, une mauvaise longueur ou un chemin dans `/nix/store`.

`programs.quickshell.earbudsAccountKeyFile` est une **chaîne de chemin**.
La clé n’est pas une entrée Nix. `system/persistance.nix` conserve son dossier ;
la copie persistante de cette installation est sous
`/persist/home/ian/.local/state/battery-relay/`.
Le backup privé de l’expérience a été conservé hors du dépôt. Une perte de clé
se résout d’abord par restauration de cette même clé, pas par un reset.

```sh
nix build --no-link .#batteryRelayReceiver .#quickshellDesktop
# Appliquer la configuration par le rebuild habituel.
qs ipc -c top-bar call topbar batteryStatus
```

Le résultat IPC doit donner `earbudSource: "fast-pair"` et `earbudMode: "passive"`. Ni l’ancien lecteur
RFCOMM ni le widget Android ne servent de secours. L’application Android n’a
pas besoin de fonctionner pour les écouteurs ; elle reste nécessaire au téléphone
et au Fitbit.

Le récepteur enregistre un moniteur `or_patterns` sur le champ AD 0x16,
préfixes `2c fe 10` (UUID FE2C puis version BATT) ou `10`. Le second couvre le
filtrage logiciel de BlueZ 5.87, dont `match_service()` compare le contenu après
retrait de l'UUID, contrairement au filtrage noyau/contrôleur. Ce préfiltre est
volontairement large : le lecteur sélectionne ensuite strictement UUID FE2C,
vérifie le filtre
de clé et déchiffre comme auparavant. Un DeviceFound vivant est obligatoire
avant de lire les propriétés de cette adresse ; parcourir l'ancien cache BlueZ
ne suffit jamais à créer une présence. Aucun pourcentage n'est conservé sur disque.

DeviceLost retire la source concernée (délai demandé : 180 secondes), sans
retirer une autre source encore présente. L'état est rapporté toutes les
30 secondes : `receivedAt` avance, pas la date `observedAt` d'un contenu inchangé.
**Une absence de variation du pourcentage n’est pas une panne.** La vue expire
un lecteur silencieux après 180 secondes et l'efface sur EOF/arrêt. Après une
suspension de sa boucle, le lecteur recrée un moniteur pour obtenir une présence
actuelle avant de publier à nouveau.

L'API est expérimentale dans BlueZ 5.87 : `system/bluetooth.nix` expose les
interfaces D-Bus avec `settings.General.Experimental = true`, sans activer
KernelExperimental. L'absence d'API donne une erreur explicite ; il n'existe
aucun repli vers un scan actif. Voir [le test de coexistence](../receiver/README.md),
qui vérifie aussi `Discovering: false` et la reconnexion de la souris.
Le profil expérimental de mesure de distance `rap`, inutile aux moniteurs, reste
exclu avec `hardware.bluetooth.disabledPlugins = ["rap"]`. Son exclusion seule
n'avait pas réparé l'ancien relais GATT du téléphone : les erreurs d'authentification
persistaient. Depuis Android/récepteur 0.6.0, le téléphone émet lui aussi des
annonces non connectables ; les deux lecteurs partagent `observer.rs`, sans GATT
ni scan actif. Cela ne modifie ni le protocole BATT ni la clé des écouteurs.
Ne pas ajouter d'appairage ou d'agent d'acceptation automatique pour lire des batteries.

BlueZ expose un dictionnaire de ServiceData, pas un paquet HCI brut ni
l’horodatage de mesure interne des écouteurs. `observedAt` représente la dernière
observation traitée sur le PC ; ne pas le présenter comme l’heure de la mesure
physique ni compter chaque signal comme un paquet radio indépendant.

## 6. Tests sans modifier les appareils

```sh
nix develop .#rust --command cargo test --locked --manifest-path tools/battery-relay/receiver/Cargo.toml
nix develop .#rust --command cargo clippy --locked --manifest-path tools/battery-relay/receiver/Cargo.toml --all-targets -- -D warnings
nix develop .#rust --command cargo test --locked --manifest-path tools/battery-relay/pairing/Cargo.toml
nix develop .#rust --command cargo clippy --locked --manifest-path tools/battery-relay/pairing/Cargo.toml --all-targets -- -D warnings
nix develop .#desktop --command node desktop/tests/run.mjs
```

Les vecteurs des tests utilisent une **clé fictive**, jamais celle de l’utilisateur.
Le helper `decode-file` peut relire les captures NDJSON privées de l’expérience
avec le même décodeur que la production ; il n’émet aucune opération Bluetooth.
Il ne faut jamais lancer `pair-existing` comme un test de compilation.
