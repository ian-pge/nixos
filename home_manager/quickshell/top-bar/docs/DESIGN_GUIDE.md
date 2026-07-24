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
- Le style conserve les neutres sombres de Catppuccin ; la capsule centrale utilise une palette sémantique rose/jaune, sauf les lanceurs applications/onglets et les widgets updates, Wi-Fi, Bluetooth, volume et luminosité qui reprennent l’accent de leur capsule latérale. Le liseré animé reste rose.

## 2. Architecture à préserver

### Fichiers principaux

- `../shell.qml` : instancie un `StatusData` partagé et un `Bar` par écran.
- `../StatusData.qml` : source d’état globale, processus externes, timers, IPC et exclusivité entre overlays.
- `../Bar.qml` : géométrie de la barre, capsule centrale, animations globales et liseré d’activité.
- `../components/WorkspaceSwitcher.qml` : workspaces normaux et slot des special workspaces.
- `../components/Theme.js` : source unique des couleurs QML, y compris les accents partagés entre capsules latérales et widgets centraux correspondants.
- `../components/VolumeIndicator.qml` / `BrightnessIndicator.qml` : indicateurs temporaires.
- `../components/NowPlayingIndicator.qml` : média MPRIS et métadonnées textuelles.
- `../components/AppLauncher.qml` : lanceur natif, icônes et recherche fuzzy.
- `../components/ChromeTabsLauncher.qml` : recherche et activation des onglets Chrome via TabCtl.
- `../components/WifiSelector.qml` / `BluetoothSelector.qml` : sélecteurs clavier.
- `../components/UpdateSelector.qml` : liste des mises à jour.
- `../components/Pill.qml` : capsule générique des modules latéraux.
- `../scripts/system-stats.py` : télémétrie persistante CPU, mémoire, disque et luminosité.
- `../../helpers/` : paquets Nix optimisés et nommés pour Quickshell.

### État partagé, rendu ciblé par écran

`StatusData` est unique pour toute la session. Chaque écran possède son propre `Bar`, mais tous lisent le même état et comparent leur `monitorName` à la cible de l’overlay.

Conséquences :

- Wi-Fi, Bluetooth, volume, luminosité, média, lanceur, onglets Chrome et updates apparaissent uniquement sur leur moniteur cible.
- Les autres écrans continuent d’afficher leur `WorkspaceSwitcher` et ne transforment pas leur capsule centrale.
- Les propriétés `wifiTargetMonitor`, `bluetoothTargetMonitor`, `appLauncherTargetMonitor`, `chromeTabsTargetMonitor`, `updateTargetMonitor`, `volumeTargetMonitor`, `brightnessTargetMonitor` et `mediaTargetMonitor` pilotent à la fois le rendu et, pour les sélecteurs interactifs, le focus clavier.
- Un clic sur une capsule latérale transmet toujours le nom du moniteur de cette barre. Un raccourci IPC sans cible utilise le moniteur Hyprland actuellement focalisé.
- Activer un overlay déjà ouvert depuis un autre écran le déplace vers ce nouvel écran ; l’activer à nouveau sur son écran courant le ferme.
- Tant qu’un widget central applications, updates, Wi-Fi, Bluetooth, volume ou luminosité est visible, sa capsule latérale correspondante adopte visuellement son état hover sur le même moniteur.

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
| Largeur média / updates / lanceurs | `480px` |
| Hauteur lanceur applications / onglets | `398px` |
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

`components/Theme.js` est l’unique source des couleurs QML de la barre :

| Token | Couleur | Signification |
|---|---|---|
| `Theme.action` | `#ff33cc` | action, sélection, focus et valeur manipulée |
| `Theme.state` | `#ffcc33` | état persistant, connecté, occupé, actif ou opération en cours |
| `Theme.error` | `#ed8796` | erreur uniquement |
| `Theme.foreground` | `#cad3f5` | texte principal |
| `Theme.selectedForeground` | `#ffffff` | texte principal sur une ligne sélectionnée |
| `Theme.secondary` | `#939ab7` | métadonnée, compteur ou information secondaire |
| `Theme.inactive` | `#6e738d` | état inactif ou vide |
| `Theme.background` | `#181926` | fond principal |
| `Theme.surface` | `#24273a` | surface secondaire |
| `Theme.surfaceRaised` | `#363a4f` | séparateur, piste ou survol |
| `Theme.surfaceSelected` | `#494d64` | surface interne sélectionnée |

Règle sémantique de la capsule centrale :

- **rose** : ce que l’utilisateur contrôle maintenant — workspace affiché, ligne sélectionnée et action Enter hors exceptions contextuelles ;
- **jaune** : ce qui existe ou fonctionne indépendamment de la sélection — workspace occupé, lecture et traitement en cours hors exceptions contextuelles ;
- **gris** : compteurs, URL, métadonnées, état vide ou inactif ;
- **rouge** : échec explicite uniquement, jamais une action normale.

Les widgets centraux applications, onglets Chrome, updates, Wi-Fi, Bluetooth, volume et luminosité sont des exceptions contextuelles. Les deux lanceurs utilisent `Theme.sideApplications` ; les autres reprennent respectivement `Theme.sideUpdates`, `Theme.sideNetwork`, `Theme.sideBluetooth`, `Theme.sideVolume` et `Theme.sideBrightness`. Cela couvre les icônes, sélections, indicateurs actifs et remplissages. Ils n’utilisent ni `Theme.action` ni `Theme.state`. Le liseré animé qui tourne autour de la capsule centrale reste rose.

Les compteurs ne changent pas de couleur selon leur quantité. Les icônes d’applications et favicons conservent naturellement leurs couleurs d’origine, car ce sont des contenus externes et non des accents d’interface.

Les capsules latérales ne changent pas de couleur selon leur état et conservent les accents fixes d’origine déclarés dans `Theme.js`. Les six accents contextuels ci-dessus sont partagés avec leur widget central correspondant. `Pill.forceHovered` reproduit l’inversion visuelle du hover pendant que le widget central associé est ouvert, sans afficher artificiellement son tooltip :

| Capsule | Token | Couleur |
|---|---|---|
| Applications | `Theme.sideApplications` | `#7dc4e4` |
| Updates | `Theme.sideUpdates` | `#f0c6c6` |
| Réseau | `Theme.sideNetwork` | `#ee99a0` |
| Bluetooth | `Theme.sideBluetooth` | `#8aadf4` |
| Disque | `Theme.sideDisk` | `#f5a97f` |
| CPU | `Theme.sideCpu` | `#91d7e3` |
| Mémoire | `Theme.sideMemory` | `#c6a0f6` |
| GPU | `Theme.sideGpu` | `#a6da95` |
| Batterie | `Theme.sideBattery` | `#f4dbd6` |
| Volume | `Theme.sideVolume` | `#b7bdf8` |
| Luminosité | `Theme.sideBrightness` | `#eed49f` |
| Météo | `Theme.sideWeather` | `#f5bde6` |
| Date | `Theme.sideDate` | `#8bd5ca` |
| Heure | `Theme.sideTime` | `#ed8796` |

Ne pas écrire de nouveau littéral hexadécimal dans un fichier QML : ajouter ou réutiliser un token de `Theme.js`. Le shader du liseré et les couleurs de bordure Hyprland sont des systèmes séparés.

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

Cette interpolation monotone est commune aux transformations entre workspaces, volume, luminosité, média, Wi-Fi, Bluetooth, updates, lanceur d’applications et onglets Chrome.

Ne pas réintroduire :

- `Easing.OutBack`, `SpringAnimation` ou une propriété `overshoot` ;
- une cible intermédiaire au-delà de la géométrie finale ;
- une séquence aller-retour pour simuler un rebond ;
- un état ou timer temporaire tel que `updateMorphGentle` / `updateMorphTimer`.

Les animations secondaires suivent la même règle : le hover et les interactions internes peuvent translater, redimensionner ou changer d’opacité, mais toujours avec une courbe monotone. Les pulses de scale sur les icônes volume et luminosité ont été supprimés. Le contenu central utilise une seule animation partagée, calculée depuis le widget source et le widget destination ; chaque composant ne relance jamais sa propre animation `presented`.

### Transition de contenu à deux couches

Les composants source et destination restent rendus simultanément pendant une courte fenêtre. Leurs opacités et translations sont calculées depuis un unique `transitionProgress` de `0` à `1`; aucun composant ne possède son propre `Behavior on opacity` ou timer d’entrée.

Le conteneur, le clipping et la bordure restent persistants. Seuls les contenus se croisent à l’intérieur, comme dans une container transform. Une répétition du même mode sur le même moniteur ne redémarre pas la transition. En cas d’interruption, les opacités et offsets actuellement rendus des neuf modes sont capturés dans des tables ; la nouvelle destination continue depuis sa valeur courante et toutes les autres couches encore visibles terminent leur fade au lieu de disparaître brutalement. Cette règle reste valable même pour une séquence très rapide A → B → C → D.

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
- onglets Chrome ;
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

Son ouverture et sa fermeture utilisent la même timeline de `360ms` que les
autres transformations Quickshell : la largeur de la capsule suit
`Easing.OutCubic`, l’entrée du slot passe de `0 → 1` entre `18 %` et `78 %`, et
sa sortie de `1 → 0` entre `0 %` et `48 %`. Comme la hauteur reste identique,
il n’y a pas de translation verticale. Les huit slots normaux restent stables
pendant l’élargissement, le nom du special workspace reste rendu jusqu’à la fin
du fade de sortie, et une interruption repart de l’opacité courante.

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

- Wi-Fi : icône et point de connexion utilisent `Theme.sideNetwork` ;
- Bluetooth : icône, point de connexion et onglets `PAIRED` / `NEARBY` utilisent `Theme.sideBluetooth` ;
- tout appareil ou réseau non connecté reste gris ;
- cadenas Wi-Fi : même gris que le compteur (`#939ab7`) ;
- le liseré animé autour de la capsule reste rose, indépendamment du widget affiché.

## 11. Lanceur d’applications

Le raccourci `Super+A` et le logo Nix à gauche ouvrent `AppLauncher.qml` dans la capsule centrale. Le lanceur utilise exclusivement `DesktopEntries.applications` et `DesktopEntry.execute()` : ne pas réintroduire Fuzzel ou une analyse périodique des fichiers `.desktop`.

Conventions :

- largeur `480px`, hauteur `398px` et huit lignes visibles ;
- toutes les applications non marquées `NoDisplay` restent accessibles avec une icône issue du thème ;
- le catalogue normalisé est construit une seule fois, puis la recherche fuzzy s’effectue en mémoire ;
- le `ListView` virtualise les lignes pour ne charger que les icônes visibles ;
- haut/bas, `Ctrl+n/p`, `Ctrl+j/k`, PageUp/PageDown et molette naviguent ;
- l’icône de recherche, la sélection de texte et le point d’une application déjà ouverte utilisent `Theme.sideApplications` ;
- aucune flèche d’action n’est affichée sur la ligne sélectionnée ;
- `Enter` active la fenêtre ouverte la plus récemment utilisée, sinon lance l’application ;
- `Ctrl+Enter` lance toujours une nouvelle instance et `Esc` ferme ;
- le texte saisi doit toujours rester du texte de recherche : ne pas réserver `j`, `k` ou `q`.

### Onglets Chrome

`Super+;` ouvre `ChromeTabsLauncher.qml` avec la même géométrie et les mêmes conventions de recherche que le lanceur d’applications. La liste provient de TabCtl 2 via son extension Chrome Manifest V3, Native Messaging puis D-Bus.

- `tabctl --format json list` est encapsulé par `quickshell-chrome-tabs` afin que QML reçoive toujours un objet JSON, y compris lorsque Chrome est fermé ou que l’extension n’est pas encore connectée ;
- le catalogue contient le titre, l’URL, la fenêtre, l’index et les états actif/épinglé ;
- les favicons sont extraits localement du SQLite `Default/Favicons` de Chrome vers `$XDG_CACHE_HOME/quickshell/chrome-favicons`, sans requête réseau ; si l’icône manque, le logo Chrome est gris pour un onglet inactif et `Theme.sideApplications` pour l’onglet actif ;
- l’icône de recherche, la sélection de texte, l’épingle et le point d’onglet actif utilisent aussi `Theme.sideApplications`, comme le lanceur d’applications ;
- aucune flèche d’action n’est affichée sur la ligne sélectionnée ;
- la recherche fuzzy porte sur le titre et l’URL ;
- `Enter` appelle `tabctl activate --focused`, `Ctrl+W` ferme l’onglet, `Ctrl+R` recharge la liste et `Esc` ferme le widget ;
- clic gauche : activation ; clic droit : fermeture ;
- huit lignes complètes sont visibles et le `ListView` reste virtualisé ;
- l’extension TabCtl est installée manuellement depuis le Chrome Web Store ; seul le manifeste `tabctl_mediator.json` est géré par Home Manager, donc ne jamais exécuter `tabctl install` manuellement.

## 12. Volume et luminosité

- Largeur `280px`, hauteur `36px`.
- Aucun pourcentage dans le widget central.
- Timeout de visibilité : `2000ms`.
- La barre de progression anime sa largeur en `140ms`.
- Les valeurs volume utilisent directement `Quickshell.Services.Pipewire`, y compris les touches XF86 et le mute ; aucun `wpctl` ne doit être réintroduit.
- La luminosité reste pilotée par `brightnessctl`, faute de service Quickshell natif.
- Le volume utilise `Theme.sideVolume` pour son icône et son remplissage.
- La luminosité utilise `Theme.sideBrightness` pour son icône et son remplissage.
- Les barres de progression ne possèdent aucun curseur ou point blanc : seul le remplissage coloré indique le niveau.
- Chaque indicateur central apparaît uniquement sur le moniteur qui a reçu la touche ou le geste de molette.

## 13. Contrôles média MPRIS

Les touches média utilisent `Quickshell.Services.Mpris`, jamais un processus `playerctl`.

`StatusData.mprisPlayer` préfère le contrôleur D-Bus `playerctld`, qui conserve la notion de dernier lecteur actif lorsque plusieurs applications ou onglets publient MPRIS. En son absence, la sélection tombe sur le lecteur en cours de lecture, puis un lecteur en pause.

Les raccourcis Hyprland appellent les méthodes IPC `mediaPlayPause`, `mediaNext` et `mediaPrevious`. Chaque méthode vérifie les capacités du lecteur avant l’action.

`NowPlayingIndicator.qml` occupe `480px`, comme le lanceur d’applications. Il affiche quatre petites barres d’égaliseur animées, puis le titre et l’artiste sur une seule ligne centrée au format `Titre • Artiste`, sans pochette, avec l’action play/pause à droite. Le texte utilise la même taille de `16px` que les capsules latérales et l’égaliseur garde une marge gauche de `15px`. Les barres sont jaunes et animées pendant la lecture, puis deviennent grises et restent basses en pause ; l’icône d’action play/pause reste rose. Le widget reste visible `4000ms` après une action média ou un changement de piste. Un changement automatique de piste ne doit jamais interrompre un sélecteur interactif Wi-Fi, Bluetooth, lanceur d’applications, onglets Chrome ou updates.

## 14. Exclusivité entre overlays

Un seul mode central peut être actif à la fois.

Lors de l’ouverture d’un overlay :

- fermer les lanceurs via `hideAppLauncher()` et `hideChromeTabs()` ;
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
- haut/bas, `Ctrl+n/p` ou `Ctrl+j/k` : navigation
- PageUp/PageDown : saut de huit résultats
- `Enter` : activer l’instance ouverte, sinon lancer
- `Ctrl+Enter` : lancer une nouvelle instance
- `Esc` : fermeture

### Onglets Chrome — `Super+;`

- saisir directement pour filtrer titre et URL
- haut/bas, `Ctrl+n/p` ou `Ctrl+j/k` : navigation
- PageUp/PageDown : saut de huit résultats
- `Enter` : activer l’onglet et focaliser sa fenêtre Chrome
- `Ctrl+W` : fermer l’onglet sélectionné
- `Ctrl+R` : recharger la liste
- clic droit : fermer l’onglet
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

Le widget central utilise `Theme.sideUpdates` pour les icônes, les états `CHECKING` / `AVAILABLE` et les points de chaque ligne. `UP TO DATE`, les dates et les états vides restent gris ; le liseré animé autour de la capsule reste rose.

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
cp -R "$PWD/home_manager/quickshell/top-bar/." "$test_config/"
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
nix-instantiate --parse home_manager/hyprland.nix >/dev/null
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
qs --config top-bar ipc call topbar toggleChromeTabs
```

### Validation TabCtl

```bash
tabctl status
quickshell-chrome-tabs list | jq '{ok, count: (.tabs | length), error}'
pgrep -af tabctl-mediator
```

`tabctl status` doit annoncer la même version de protocole pour le médiateur et l’extension. Tester manuellement `Enter`, `Ctrl+W`, `Ctrl+R`, le clic droit et le déplacement de l’overlay entre les deux moniteurs ; ne jamais fermer automatiquement un onglet utilisateur pendant une validation.

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
