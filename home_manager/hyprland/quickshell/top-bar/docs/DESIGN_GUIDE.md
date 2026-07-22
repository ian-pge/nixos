# Guide visuel et conventions d’animation — barre Quickshell

Ce document décrit les décisions visuelles, les conventions d’animation et les pièges déjà rencontrés pour la barre située dans le dossier parent. Il est destiné en priorité à une future IA qui devra modifier le widget sans casser sa cohérence.

## 1. Intention générale

La barre doit donner l’impression d’être un seul système animé, pas une collection de popups indépendants.

Principes fondamentaux :

- La capsule centrale est un objet unique qui **se transforme** entre workspaces, volume, luminosité, média MPRIS, lanceur d’applications, Wi-Fi, Bluetooth et mises à jour.
- Les changements de taille utilisent une interpolation monotone sans rebond.
- Le contenu source et le contenu destination coexistent brièvement dans une transition croisée pilotée par la même progression que la capsule.
- Une transformation doit entraîner son contenu avec elle. Les éléments ne doivent pas sembler flotter indépendamment de leur capsule.
- Tous les overlays sont visibles uniquement sur l’écran qui les a activés ; les workspaces restent visibles sur les autres écrans.
- Le style conserve les neutres sombres de Catppuccin, mais la capsule centrale utilise exclusivement les accents rose néon et jaune néon des workspaces.

## 2. Architecture à préserver

### Fichiers principaux

- `../shell.qml` : instancie un `StatusData` partagé et un `Bar` par écran.
- `../StatusData.qml` : source d’état globale, processus externes, timers, IPC et exclusivité entre overlays.
- `../Bar.qml` : géométrie de la barre, capsule centrale, animations globales et liseré d’activité.
- `../components/WorkspaceSwitcher.qml` : workspaces normaux et slot des special workspaces.
- `../components/VolumeIndicator.qml` / `BrightnessIndicator.qml` : indicateurs temporaires.
- `../components/NowPlayingIndicator.qml` : média MPRIS et métadonnées textuelles.
- `../components/AppLauncher.qml` : lanceur natif, icônes et recherche fuzzy.
- `../components/WifiSelector.qml` / `BluetoothSelector.qml` : sélecteurs clavier.
- `../components/UpdateSelector.qml` : liste des mises à jour.
- `../components/Pill.qml` : capsule générique des modules latéraux.
- `../scripts/system-stats.py` : télémétrie persistante CPU, mémoire, disque et luminosité.
- `../../helpers/` : paquets Nix optimisés et nommés pour Quickshell.

### État partagé, rendu ciblé par écran

`StatusData` est unique pour toute la session. Chaque écran possède son propre `Bar`, mais tous lisent le même état et comparent leur `monitorName` à la cible de l’overlay.

Conséquences :

- Wi-Fi, Bluetooth, volume, luminosité, média, lanceur et updates apparaissent uniquement sur leur moniteur cible.
- Les autres écrans continuent d’afficher leur `WorkspaceSwitcher` et ne transforment pas leur capsule centrale.
- Les propriétés `wifiTargetMonitor`, `bluetoothTargetMonitor`, `appLauncherTargetMonitor`, `updateTargetMonitor`, `volumeTargetMonitor`, `brightnessTargetMonitor` et `mediaTargetMonitor` pilotent à la fois le rendu et, pour les sélecteurs interactifs, le focus clavier.
- Un clic sur une capsule latérale transmet toujours le nom du moniteur de cette barre. Un raccourci IPC sans cible utilise le moniteur Hyprland actuellement focalisé.
- Activer un overlay déjà ouvert depuis un autre écran le déplace vers ce nouvel écran ; l’activer à nouveau sur son écran courant le ferme.

## 3. Géométrie canonique

| Élément | Valeur |
|---|---:|
| Hauteur normale d’une capsule | `36px` |
| Rayon normal | `18px` |
| Marge supérieure du panel | `10px` |
| Marges latérales du panel | `5px` |
| Espacement entre modules latéraux | `10px` |
| Largeur volume/luminosité | `280px` |
| Largeur Wi-Fi/Bluetooth | `400px` |
| Largeur média / updates / lanceur | `480px` |
| Hauteur lanceur | `398px` |
| Hauteur d’une ligne update | `30px` |
| Hauteur d’une ligne application | `42px` |

### Surface layer-shell fixe

Le `PanelWindow` garde une hauteur fixe de `600px`, même lorsque la capsule ne fait que `36px`.

C’est volontaire : animer la hauteur du `PanelWindow` provoquait un léger déplacement vertical des autres modules à cause des recalculs du layer-shell et des arrondis du compositeur.

À respecter :

- `implicitHeight: 600`
- `exclusiveZone: 36`
- marge supérieure de `10px`, donc réserve Hyprland effective de `46px`
- `mask: Region` limité à `leftModules`, `centerMorph` et `rightModules`

La zone transparente inutilisée doit rester click-through. **Ne pas recommencer à animer la hauteur du `PanelWindow`.** Seule la hauteur de `centerMorph` est animée.

### Croissance verticale

`centerMorph` est ancré en haut :

```qml
anchors.horizontalCenter: parent.horizontalCenter
anchors.top: parent.top
```

Ainsi, le widget update grandit uniquement vers le bas, jamais vers le haut.

## 4. Palette visuelle

Couleurs de référence de la capsule centrale :

| Usage | Couleur |
|---|---|
| Fond principal | `#181926` |
| Surface secondaire | `#363a4f` |
| Surface tertiaire | `#24273a` / `#494d64` |
| Texte principal | `#cad3f5` |
| Texte secondaire / compteurs / cadenas | `#939ab7` |
| Élément neutre discret | `#6e738d` |
| Rose néon, accent principal | `#ff33cc` |
| Jaune néon, accent secondaire | `#ffcc33` |

La capsule centrale suit une palette volontairement bi-accent :

- le rose identifie les actions, la sélection, les éléments disponibles et les erreurs ;
- le jaune indique les états connectés, actifs ou en cours, et sert d’accent secondaire ;
- les nuances neutres Catppuccin restent autorisées pour les fonds, le texte, les séparateurs et les états inactifs ;
- aucun autre accent Catppuccin (bleu, vert, rouge saumon, mauve, etc.) ne doit être introduit dans les workspaces, volume, luminosité, média, Wi-Fi, Bluetooth, updates ou lanceur.

Cette restriction concerne la capsule centrale. Les capsules latérales conservent pour l’instant leurs accents propres.

Police : `Ubuntu Nerd Font`.

Les libellés importants sont en gras. Le nom d’un special workspace utilise `Font.Black`.

## 5. Contrat d’animation de la capsule centrale

### Transformation générale

La largeur et la hauteur de `centerMorph` suivent directement leur cible avec une interpolation monotone, dans le même esprit que les animations `popin`, slide et fade de Hyprland : mouvement rapide au départ, décélération propre, aucun dépassement puis retour arrière.

Pour chaque changement de géométrie, à l’ouverture comme à la fermeture :

- `Behavior on width` et `Behavior on height` indépendants ;
- durée `360ms` ;
- `Easing.OutCubic` ;
- aucun overshoot, rebond, ressort ou phase de stabilisation ;
- si la cible change en cours de mouvement, Qt repart automatiquement de la valeur actuellement affichée.

Une dimension qui ne change pas ne doit pas être animée. La capsule ne doit jamais franchir sa cible avant de revenir.

### Convention unique pour tous les widgets

Cette interpolation monotone est commune aux transformations entre workspaces, volume, luminosité, média, Wi-Fi, Bluetooth, updates et lanceur d’applications.

Ne pas réintroduire :

- `Easing.OutBack`, `SpringAnimation` ou une propriété `overshoot` ;
- une cible intermédiaire au-delà de la géométrie finale ;
- une séquence aller-retour pour simuler un rebond ;
- un état ou timer temporaire tel que `updateMorphGentle` / `updateMorphTimer`.

Les animations secondaires suivent la même règle : le hover et les interactions internes peuvent translater, redimensionner ou changer d’opacité, mais toujours avec une courbe monotone. Les pulses de scale sur les icônes volume et luminosité ont été supprimés. Le contenu central utilise une seule animation partagée, calculée depuis le widget source et le widget destination ; chaque composant ne relance jamais sa propre animation `presented`.

### Transition de contenu à deux couches

Les composants source et destination restent rendus simultanément pendant une courte fenêtre. Leurs opacités et translations sont calculées depuis un unique `transitionProgress` de `0` à `1`; aucun composant ne possède son propre `Behavior on opacity` ou timer d’entrée.

Le conteneur, le clipping et la bordure restent persistants. Seuls les contenus se croisent à l’intérieur, comme dans une container transform. Une répétition du même mode sur le même moniteur ne redémarre pas la transition. En cas d’interruption, les opacités et offsets actuellement rendus des huit modes sont capturés dans des tables ; la nouvelle destination continue depuis sa valeur courante et toutes les autres couches encore visibles terminent leur fade au lieu de disparaître brutalement. Cette règle reste valable même pour une séquence très rapide A → B → C → D.

## 6. Animation contextuelle du contenu central

`StatusData` décrit chaque transaction avec le mode et le moniteur source, puis le mode et le moniteur destination. Le serial n’est incrémenté qu’après la fermeture propre de l’ancien état et l’ouverture du nouveau ; les états intermédiaires `workspaces` produits par les booléens ne doivent jamais devenir la source logique d’une transition directe.

Chaque `Bar` ramène un mode situé sur l’autre moniteur à `workspaces`, puis anime pendant les mêmes `360ms` que la géométrie :

- contenu source : opacité `1 → 0` entre `0 %` et `48 %`, déplacement de `0 → 8px` dans le sens du changement de hauteur ;
- contenu destination : opacité `0 → 1` entre `18 %` et `78 %`, déplacement de `10px → 0` dans ce même sens visuel ;
- destination plus haute : flux vers le bas ;
- destination plus basse : flux vers le haut ;
- hauteurs égales : aucune translation verticale, seulement la transition croisée et la mise en page liée à la largeur ;
- courbes d’opacité `smoothstep`, translations `OutCubic`, sans overshoot.

Ainsi launcher → updates conserve brièvement les applications pendant que la capsule rétrécit et les masque, puis le header et les lignes updates apparaissent en remontant légèrement. La transition inverse suit le mouvement descendant. Les composants gardent leur hauteur naturelle, restent top-alignés et le `clip: true` révèle ou masque le reste.

Ce système est une container transform à deux couches, pas encore un morphing élément-par-élément : les éléments partagés ne sont pas appariés individuellement.

À ne pas refaire :

- animation `presented` locale ignorant le widget source ;
- passage artificiel par `workspaces` dans les métadonnées d’une transition overlay → overlay ;
- grand déplacement proportionnel à toute la différence de hauteur ;
- fades indépendants non synchronisés, rebond ou translation dépassant les `360ms` de géométrie ;
- remise de `transitionProgress` à zéro sans capturer les opacités/offsets rendus lors d’une interruption.

## 7. Liseré rose d’activité

Le liseré apparaît lorsque `centerMorph.overlayVisible` est vrai, donc pour :

- volume ;
- luminosité ;
- Wi-Fi ;
- Bluetooth ;
- média MPRIS ;
- lanceur d’applications ;
- updates.

Il disparaît uniquement quand la capsule redevient le widget des workspaces.

### Rendu actuel

Le liseré n’utilise ni `Canvas`, ni `Repeater` de petits rectangles, ni gradient conique. Le `Repeater` demandait jusqu’à plus de mille mises à jour QML par frame sur deux écrans ; le gradient conique était plus léger mais accélérait visuellement dans les coins parce qu’un angle constant ne correspond pas à une distance constante sur un rectangle.

La version actuelle utilise un unique `ShaderEffect` et `shaders/activity-border.frag` :

- shader Qt 6 compilé en `.qsb` par `quickshell.nix` avec `qtshadertools` ;
- rectangle arrondi de rayon extérieur `18px` ;
- anneau intérieur de `2px` calculé par signed-distance field ;
- position exacte sur le périmètre calculée avec les longueurs des quatre segments et des quatre quarts de cercle ;
- traînée couvrant `50 %` du périmètre ;
- couleur de tête `#ff33cc` ;
- opacité `Math.pow(1 - behindHead / 0.5, 1.35)` ;
- phase de `0` à `1` en `1600ms`.

Les états `0` et `1` sont identiques et la coupure opaque-vers-transparent reste placée à la tête. QML ne met à jour qu’un uniforme `phase` par frame ; la géométrie, la position sur le chemin, l’anticrénelage et le dégradé sont calculés en parallèle sur le GPU. La sortie du fragment shader est prémultipliée pour respecter le blending du scene graph Qt Quick.

Le mouvement doit conserver une vitesse linéaire perceptuelle identique sur les segments et dans les coins, quelle que soit la largeur de la capsule.

## 8. Bordure Hyprland pendant un overlay

Lorsque le centre affiche un overlay, la fenêtre normale n’est plus considérée visuellement comme la cible principale.

`StatusData.centerOverlayVisible` remplace temporairement :

- bordure active verte : `rgba(33ff33ff)`
- par la bordure inactive grise : `rgba(888888aa)`

Quand l’overlay disparaît, la bordure verte est restaurée.

Toujours restaurer la bordure :

- au démarrage de `StatusData` ;
- à la fermeture du dernier overlay ;
- dans `Component.onDestruction`.

Cela évite de laisser Hyprland en gris après un redémarrage de Quickshell.

## 9. Workspaces et special workspaces

### Workspaces normaux

- 8 slots.
- Slot inactif : `40px`.
- Slot actif : `60px`.
- Hauteur : `24px`.
- Slot actif rose néon `#ff33cc` avec texte sombre.
- Les workspaces occupés utilisent le jaune ; les vides utilisent une couleur discrète.

Quand la capsule change de largeur, l’espacement entre les slots dépend de la largeur disponible. Les icônes suivent donc l’interpolation de largeur au lieu de rester figées au centre.

### Special workspace

Quand Hyprland émet `activespecial`, un slot supplémentaire apparaît à droite avec le nom sans le préfixe `special:`.

Conventions :

- fond `#ff33cc` ;
- texte `#181926`, `Font.Black` ;
- hauteur `24px`, rayon `12px` ;
- largeur minimum `70px` ;
- clic sur le slot : `togglespecialworkspace`.

Le slot n’apparaît que sur le moniteur où le special workspace est actif.

## 10. Wi-Fi et Bluetooth

### Géométrie et animation de navigation

Les deux sélecteurs doivent rester visuellement parallèles :

- largeur `400px` ;
- hauteur `36px` ;
- compteur aligné sur une hauteur fixe de `18px` ;
- animation de roue verticale en `150ms` ;
- déplacement de `40px` hors du viewport découpé ;
- easing `InOutCubic`.

La roue ne se déclenche que pour une navigation volontaire (`j/k/h/l`, flèches, `g/G` pour le Wi-Fi). Elle ne doit pas tourner lors de l’ouverture, de la fermeture, d’un scan ou d’un changement de message.

### Services natifs et scans

Le Wi-Fi utilise exclusivement `Quickshell.Networking` : devices NetworkManager, réseaux, puissance, sécurité, états, scan et connexion PSK. Aucun helper `nmcli` ne doit être réintroduit.

Le Bluetooth utilise exclusivement `Quickshell.Bluetooth` : découverte BlueZ, appareils, appairage, connexion et déconnexion. Aucun helper `bluetoothctl` ne doit être réintroduit.

À l’ouverture, les modèles natifs déjà chargés s’affichent immédiatement. Le rafraîchissement silencieux active temporairement `WifiDevice.scannerEnabled` sans spinner.

Un vrai spinner est réservé à :

- `r` pour un scan Wi-Fi explicite ;
- l’onglet Bluetooth `NEARBY`, via `BluetoothAdapter.discovering`.

### Couleurs d’état

- connecté : point jaune néon `#ffcc33` ;
- Bluetooth appairé mais déconnecté : rose néon `#ff33cc` ;
- Bluetooth non appairé : gris ;
- icônes Wi-Fi et Bluetooth : rose néon `#ff33cc` ;
- onglet Bluetooth `PAIRED` : rose néon, onglet `NEARBY` : jaune néon ;
- cadenas Wi-Fi : même gris que le compteur (`#939ab7`).

## 11. Lanceur d’applications

Le raccourci `Super+A` et le logo Nix à gauche ouvrent `AppLauncher.qml` dans la capsule centrale. Le lanceur utilise exclusivement `DesktopEntries.applications` et `DesktopEntry.execute()` : ne pas réintroduire Fuzzel ou une analyse périodique des fichiers `.desktop`.

Conventions :

- largeur `480px`, hauteur `398px` et huit lignes visibles ;
- toutes les applications non marquées `NoDisplay` restent accessibles avec une icône issue du thème ;
- le catalogue normalisé est construit une seule fois, puis la recherche fuzzy s’effectue en mémoire ;
- le `ListView` virtualise les lignes pour ne charger que les icônes visibles ;
- haut/bas, `Ctrl+n/p`, PageUp/PageDown et molette naviguent ;
- un point jaune néon `#ffcc33` indique qu’au moins une fenêtre correspondante est déjà ouverte ;
- `Enter` active la fenêtre ouverte la plus récemment utilisée, sinon lance l’application ;
- `Shift+Enter` lance toujours une nouvelle instance et `Esc` ferme ;
- le texte saisi doit toujours rester du texte de recherche : ne pas réserver `j`, `k` ou `q`.

## 12. Volume et luminosité

- Largeur `280px`, hauteur `36px`.
- Aucun pourcentage dans le widget central.
- Timeout de visibilité : `2000ms`.
- La barre de progression anime sa largeur en `140ms`.
- Les valeurs volume utilisent directement `Quickshell.Services.Pipewire`, y compris les touches XF86 et le mute ; aucun `wpctl` ne doit être réintroduit.
- La luminosité reste pilotée par `brightnessctl`, faute de service Quickshell natif.
- Le volume utilise le rose néon `#ff33cc`, ou le jaune néon `#ffcc33` lorsqu’il est muet.
- La luminosité utilise le jaune néon `#ffcc33`.
- Chaque indicateur central apparaît uniquement sur le moniteur qui a reçu la touche ou le geste de molette.

## 13. Contrôles média MPRIS

Les touches média utilisent `Quickshell.Services.Mpris`, jamais un processus `playerctl`.

`StatusData.mprisPlayer` préfère le contrôleur D-Bus `playerctld`, qui conserve la notion de dernier lecteur actif lorsque plusieurs applications ou onglets publient MPRIS. En son absence, la sélection tombe sur le lecteur en cours de lecture, puis un lecteur en pause.

Les raccourcis Hyprland appellent les méthodes IPC `mediaPlayPause`, `mediaNext` et `mediaPrevious`. Chaque méthode vérifie les capacités du lecteur avant l’action.

`NowPlayingIndicator.qml` occupe `480px`, comme le lanceur d’applications. Il affiche quatre petites barres d’égaliseur animées, puis le titre et l’artiste sur une seule ligne centrée au format `Titre • Artiste`, sans pochette, avec l’état play/pause à droite. Le texte utilise la même taille de `16px` que les capsules latérales et l’égaliseur garde une marge gauche de `15px`. Les barres restent basses lorsque le lecteur est en pause et s’animent indépendamment pendant la lecture. L’icône de lecture est jaune néon `#ffcc33` et l’icône de pause rose néon `#ff33cc`. Le widget reste visible `4000ms` après une action média ou un changement de piste. Un changement automatique de piste ne doit jamais interrompre un sélecteur interactif Wi-Fi, Bluetooth, lanceur ou updates.

## 14. Exclusivité entre overlays

Un seul mode central peut être actif à la fois.

Lors de l’ouverture d’un overlay :

- fermer le lanceur via `hideAppLauncher()` ;
- fermer Wi-Fi/Bluetooth via leurs fonctions `hide*`, jamais par mutation directe des booléens ;
- arrêter les timers volume/luminosité via `hideVolumeOverlay()` et `hideBrightnessOverlay()` ;
- fermer updates via `hideUpdateSelector()` ;
- résoudre et enregistrer le moniteur cible avant de rendre le nouvel overlay visible ;
- laisser les workspaces inchangés sur les autres écrans.

Le nettoyage Wi-Fi annule aussi le scan différé, le timer de connexion, le mot de passe et le réseau pending. Une génération de scan empêche un ancien `Qt.callLater` de réactiver le scanner après fermeture.

Une action Bluetooth native déjà lancée continue lorsque le sélecteur est masqué. Son timer et son message restent associés à l’action afin qu’une réouverture puisse afficher son état ; seule la découverte est arrêtée.

## 15. Raccourcis et contrôles

`Cmd` dans les demandes utilisateur correspond à `SUPER` dans Hyprland.

### Applications — `Super+A`

- saisir directement pour filtrer en fuzzy
- haut/bas ou `Ctrl+n/p` : navigation
- PageUp/PageDown : saut de huit résultats
- `Enter` : activer l’instance ouverte, sinon lancer
- `Shift+Enter` : lancer une nouvelle instance
- `Esc` : fermeture

### Wi-Fi — `Super+N`

- `j/l` ou bas/droite : suivant
- `k/h` ou haut/gauche : précédent
- `g/G` : début/fin
- `r` : rescan
- `Enter` : connexion
- `q/Esc` : fermeture

### Bluetooth — `Super+B`

- `Tab` : `PAIRED` / `NEARBY`
- `j/l` ou bas/droite : suivant
- `k/h` ou haut/gauche : précédent
- `r` : actualiser/scanner
- `Enter` : connecter, déconnecter ou appairer
- `q/Esc` : fermeture

### Updates — `Super+U`

- `r` : vérification forcée
- `Enter` : lance `quickshell-update-installer` dans Ghostty
- `q/Esc` : fermeture

Ne pas tester `Enter` automatiquement : cela lance réellement `nix flake update` puis `nh os switch`.

## 16. Pièges connus

1. **Animer la hauteur du `PanelWindow`** : provoque un glitch vertical du reste de la barre.
2. **Toute courbe `OutBack`, spring ou overshoot** : franchit la cible puis inverse brièvement le mouvement, contrairement au contrat monotone inspiré de Hyprland.
3. **Séquence géométrique aller-retour** : réintroduit un rebond même si chaque phase utilise séparément une courbe monotone.
4. **Canvas + line dash animé** : le liseré peut disparaître ou sauter selon sa position.
5. **`Repeater` de points proportionnel au périmètre** : multiplie les objets et les calculs JavaScript par frame sur les grands overlays et sur chaque écran.
6. **`ConicalGradient` sur le rectangle** : sa vitesse angulaire constante accélère visuellement à l’approche des coins.
7. **Committer le `.qsb` généré** : le shader binaire doit rester un produit du build Nix ; seule la source `.frag` est versionnée.
8. **Espacement négatif des lignes update** : superpose les textes.
9. **Liste update montant depuis le bas** : direction visuellement incohérente.
10. **Fades indépendants par widget** : désynchronisent les couches ; toutes les opacités doivent dépendre du `transitionProgress` partagé.
11. **Focus clavier sur tous les panels** : plusieurs surfaces se disputent le clavier.
12. **Rendre un overlay sur tous les moniteurs** : masque inutilement les workspaces des écrans qui ne l’ont pas activé.
13. **Muter directement `wifiSelectorVisible` ou `bluetoothSelectorVisible`** : contourne le nettoyage des scans, timers et états interactifs ; utiliser les fonctions `hide*`.
14. **Mot de passe Wi-Fi dans les arguments de commande** : interdit ; utiliser directement `WifiNetwork.connectWithPsk()`.
15. **Oublier de restaurer la bordure Hyprland** : laisse les fenêtres avec une bordure grise.

## 17. Procédure de validation

### Vérification QML rapide

```bash
test_config=$(mktemp -d)
cp -R "$PWD/home_manager/hyprland/quickshell/top-bar/." "$test_config/"
nix shell \
  '.#nixosConfigurations.nixos.pkgs.qt6Packages.qtshadertools' \
  -c qsb --qt6 \
  -o "$test_config/shaders/activity-border.frag.qsb" \
  "$test_config/shaders/activity-border.frag"
timeout --signal=TERM 5s qs --no-color -p "$test_config"
rm -rf "$test_config"
```

Le code doit afficher `Configuration Loaded` sans erreur QML ou shader. L’avertissement de portail `org.quickshell` est connu et non bloquant.

### Vérification Nix

```bash
nix-instantiate --parse home_manager/hyprland/hyprland.nix >/dev/null
git diff --check
git diff --cached --check
```

### Construire et activer

```bash
activation=$(nix build --print-out-paths --no-link \
  '.#nixosConfigurations.nixos.config.home-manager.users.ian.home.activationPackage' \
  | tail -1)
"$activation/activate"
systemctl --user restart quickshell.service
hyprctl reload
```

### Logs

```bash
systemctl --user is-active quickshell.service
qs log -c top-bar --no-color
```

### IPC utile

```bash
qs --config top-bar ipc call topbar showVolume
qs --config top-bar ipc call topbar showBrightness
qs --config top-bar ipc call topbar toggleWifi
qs --config top-bar ipc call topbar toggleBluetooth
qs --config top-bar ipc call topbar toggleUpdates
qs --config top-bar ipc call topbar toggleLauncher
```

### Invariants à contrôler après une animation

```bash
hyprctl -j monitors | jq 'map({name,reserved})'
hyprctl getoption general:col.active_border -j
```

La réserve supérieure doit rester `[0,46,0,0]`. Hors overlay, la bordure active doit être revenue à `ff33ff33`.

## 18. Règle finale pour une future IA

Avant toute modification visuelle, identifier clairement :

1. la géométrie qui doit bouger ;
2. le contenu qui doit suivre cette géométrie ;
3. le moniteur qui reçoit le rendu et le clavier ;
4. les autres écrans qui doivent conserver leurs workspaces sans reproduire l’animation ;
5. les limites physiques imposées par les modules latéraux ;
6. la restauration de l’état Hyprland après fermeture.

Tester l’ouverture, le milieu du mouvement, l’arrivée monotone et la fermeture. Vérifier image par image que la géométrie ne franchit jamais sa cible ; une capture finale seule ne suffit pas pour valider une animation.
