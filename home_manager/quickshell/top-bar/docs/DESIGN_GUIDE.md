# Guide visuel et conventions d’animation — barre Quickshell

Ce document décrit les décisions visuelles, les conventions d’animation et les pièges déjà rencontrés pour la barre située dans le dossier parent. Il est destiné en priorité à une future IA qui devra modifier le widget sans casser sa cohérence.

## 1. Intention générale

La barre doit donner l’impression d’être un seul système animé, pas une collection de popups indépendants.

Principes fondamentaux :

- La capsule centrale est un objet unique qui **se transforme** entre workspaces, volume, panneau audio, calendrier météo, luminosité, dictée vocale, média MPRIS, lanceur d’applications, Wi-Fi, Bluetooth, mises à jour et notifications éphémères.
- Les changements de taille utilisent une interpolation monotone sans rebond.
- Le contenu source et le contenu destination coexistent brièvement dans une transition croisée pilotée par la même progression que la capsule.
- Une transformation doit entraîner son contenu avec elle. Les éléments ne doivent pas sembler flotter indépendamment de leur capsule.
- Tous les overlays sont visibles uniquement sur l’écran qui les a activés ; les workspaces restent visibles sur les autres écrans.
- Le style conserve les neutres sombres de Catppuccin ; la capsule centrale utilise une palette sémantique rose/jaune, sauf les lanceurs applications/onglets et les widgets updates, Wi-Fi, Bluetooth, volume et luminosité qui reprennent l’accent de leur capsule latérale. Le liseré animé reste rose, sauf pour les notifications qui utilisent le jaune vif.

## 2. Architecture à préserver

### Fichiers principaux

- `../shell.qml` : instancie un `StatusData` partagé et un `Bar` par écran.
- `../StatusData.qml` : source d’état globale, processus externes, timers, IPC et exclusivité entre overlays.
- `../NotificationData.qml` : serveur natif de notifications, carte courante et expiration, partagé via `StatusData.notifications`.
- `../WeatherData.qml` : température et météo quotidienne partagées, actualisation et état du cache.
- `../components/CalendarPanel.qml` / `Calendar.js` : calendrier mensuel et calculs de dates locales, icônes météo monochromes et températures mini/maxi.
- `../components/NotificationPopup.qml` / `NotificationInputGuard.qml` : carte avec image et protection du focus du panneau masqué.
- `../Bar.qml` : géométrie de la barre, capsule centrale, animations globales et liseré d’activité.
- `../OsdOverlay.qml` : indicateurs temporaires au-dessus des fenêtres plein écran.
- `../components/WorkspaceSwitcher.qml` : workspaces normaux et slot des special workspaces.
- `../components/Theme.js` : source unique des couleurs QML, y compris les accents partagés entre capsules latérales et widgets centraux correspondants.
- `../components/VolumeIndicator.qml` / `BrightnessIndicator.qml` : indicateurs temporaires.
- `../components/AudioSelector.qml` : choix des sorties et du micro sur une page.
- `../components/VoiceDictationIndicator.qml` / `VoiceWaveform.qml` : états Voxtype et rendu de l’onde vocale alimentée par le bridge audio partagé.
- `../components/NowPlayingIndicator.qml` : média MPRIS et métadonnées textuelles.
- `../components/AppLauncher.qml` : lanceur natif, icônes et recherche fuzzy.
- `../components/ChromeTabsLauncher.qml` : recherche et activation des onglets Chrome via TabCtl.
- `../components/WifiSelector.qml` / `BluetoothSelector.qml` : sélecteurs clavier.
- `../components/UpdateSelector.qml` : liste des mises à jour.
- `../components/Pill.qml` : capsule générique des modules latéraux.
- `../components/SelectionBounce.qml` : rebond partagé des éléments sélectionnés.
- `../../../../tools/quickshell/system-stats/` : télémétrie Rust persistante CPU, mémoire, disque et luminosité.
- `../../../../tools/quickshell/chrome-tabs/` : adaptateur Rust TabCtl et cache local des favicons Chrome.
- `../../../../tools/README.md` : sources et tests organisés par outil logique.
- `../../../../packages/default.nix` : catalogue des paquets exposés par `localPackages`, avec une recette Nix par outil.

### État partagé, rendu ciblé par écran

`StatusData` est unique pour toute la session. Chaque écran possède son propre `Bar`, mais tous lisent le même état et comparent leur `monitorName` à la cible de l’overlay.

Conséquences :

- Wi-Fi, Bluetooth, volume, luminosité, dictée, média, lanceur, onglets Chrome et updates apparaissent uniquement sur leur moniteur cible.
- Les autres écrans continuent d’afficher leur `WorkspaceSwitcher` et ne transforment pas leur capsule centrale.
- Les propriétés `wifiTargetMonitor`, `bluetoothTargetMonitor`, `appLauncherTargetMonitor`, `chromeTabsTargetMonitor`, `updateTargetMonitor`, `volumeTargetMonitor`, `brightnessTargetMonitor`, `voiceDictationTargetMonitor` et `mediaTargetMonitor` pilotent à la fois le rendu et, pour les sélecteurs interactifs, le focus clavier.
- Un clic sur une capsule latérale transmet toujours le nom du moniteur de cette barre. Un raccourci IPC sans cible utilise le moniteur Hyprland actuellement focalisé.
- Activer un overlay déjà ouvert depuis un autre écran le déplace vers ce nouvel écran ; l’activer à nouveau sur son écran courant le ferme.
- Tant qu’un widget central applications, updates, Wi-Fi, Bluetooth, volume ou luminosité est visible, sa capsule latérale correspondante adopte visuellement son état hover sur le même moniteur.

## 3. Géométrie canonique

| Élément | Valeur |
|---|---:|
| Hauteur normale d’une capsule | `36px` |
| Rayon normal | `18px` |
| Décalage supérieur du contenu dans le panel | `10px` |
| Marges latérales du panel | `5px` |
| Espacement entre modules latéraux | `10px` |
| Capsule latérale avec icône seule | `36×36px` |
| Largeur dictée vocale | `180px` |
| Largeur volume/luminosité | `280px` |
| Plafond Wi-Fi/Bluetooth | `400px` |
| Plafond commun à tous les widgets centraux | Largeur des workspaces avec un slot spécial (`WorkspaceSwitcher.expandedImplicitWidth`) |
| Largeur souhaitée audio / lanceurs applications / onglets | `480px`, limitée par le plafond commun |
| Plafond souhaité média / updates | `480px`, limité par le plafond commun |
| Largeur souhaitée notification | `160–480px` selon le texte, limitée par le plafond commun |
| Largeur calendrier | Exactement le plafond commun des workspaces |
| Hauteur calendrier | Ajustée aux 4–6 semaines et à leur contenu météo, au plus `492px` |
| Hauteur lanceur applications / onglets | `398px` |
| Hauteur d’une ligne update | `30px` |
| Hauteur d’une ligne application | `42px` |

`centerMorph` limite systématiquement la largeur souhaitée du contenu à
`WorkspaceSwitcher.expandedImplicitWidth` : les huit slots normaux, leurs marges,
plus un slot spécial et son espacement. Ce plafond est calculé même sans special
workspace ouvert ; le slot vide utilise alors sa largeur minimum de `70px`.
Avec un workspace normal focalisé et ce slot minimum, le plafond vaut `434px`.
Si le nom du special workspace exige davantage de place, sa largeur réelle sert
de référence. Ne pas recopier une constante en pixels dans chaque widget.

Les sélecteurs textuels, le média, les updates et les notifications mesurent leur contenu avec
`FontMetrics` et adaptent leur largeur en direct, dans leurs propres limites
puis sous ce plafond commun. Les panneaux audio et les lanceurs de recherche
demandent `480px`, mais occupent au maximum la largeur de référence des workspaces.
Les contenus suivent la largeur réelle de la capsule ; les libellés trop longs
sont élidés et les listes conservent leur défilement. Les widgets à barre longue —
dictée vocale, volume et luminosité — conservent eux aussi leur largeur fixe ;
le Wi-Fi reste à `400px` pendant un speed test afin de ne pas redimensionner sa
barre de progression.

Une capsule latérale composée uniquement d'une icône est toujours un cercle
strict de `36×36px`, indépendamment de la chasse du glyphe Nerd Font.
Applications, updates, Wi-Fi et Bluetooth utilisent ce mode en permanence. La
capsule audio reste textuelle même muette, avec pourcentage et état du micro.
Le contenu est centré horizontalement et
verticalement dans toute la surface. La capsule update latérale conserve une
icône statique pendant les opérations : les animations Braille sont réservées
au widget central. Les capsules textuelles gardent `20px` de padding mais ne
peuvent jamais mesurer moins de `36px` de large.

Les indicateurs CPU, RAM, GPU et disque forment une seule `Pill`, dans cet ordre,
à gauche. Température météo, date et heure forment une seconde `Pill`, à droite.
Chaque groupe utilise un unique libellé avec trois espaces entre les indicateurs,
un seul fond et le rebond commun au groupe entier. Conserver les icônes, formats
et mises à jour des données existants. La capsule système n’a pour l’instant
aucune action au clic et ne lance plus `htop`, `nvtop` ou `ncdu`. La capsule
température/date/heure ouvre le calendrier météo central.

### Surface layer-shell fixe

Le `PanelWindow` garde une hauteur fixe de `860px`, même lorsque la capsule ne fait que `36px`.

C’est volontaire : animer la hauteur du `PanelWindow` provoquait un léger déplacement vertical des autres modules à cause des recalculs du layer-shell et des arrondis du compositeur.

À respecter :

- `implicitHeight: 850 + barTopInset`, avec `barTopInset: 10`
- `exclusiveZone: 36 + barTopInset`, soit une réserve Hyprland de `46px`
- marge supérieure du panel de `0px`, contenu décalé de `10px` à l’intérieur
- `mask: Region` limité à `leftModules`, `centerMorph` et `rightModules`

La zone transparente inutilisée doit rester click-through. **Ne pas recommencer à animer la hauteur du `PanelWindow`.** Seule la hauteur de `centerMorph` est animée.

L’espace au-dessus des capsules appartient à la surface du panel afin que leur
rebond vers le haut reste visible. Leur position au repos et la réserve pour
les fenêtres restent identiques.

### Croissance verticale

`centerMorph` est ancré en haut :

```qml
anchors.horizontalCenter: parent.horizontalCenter
anchors.top: parent.top
anchors.topMargin: window.barTopInset
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
- **rouge** : échec explicite, sauf l’exception volontaire du microphone pendant l’enregistrement.

Les widgets centraux applications, onglets Chrome, updates, Wi-Fi, Bluetooth, volume, luminosité et calendrier sont des exceptions contextuelles. Les deux lanceurs utilisent `Theme.sideApplications` ; les autres reprennent respectivement `Theme.sideUpdates`, `Theme.sideNetwork`, `Theme.sideBluetooth`, `Theme.sideVolume`, `Theme.sideBrightness` et `Theme.sideWeather`. Cela couvre les icônes, sélections, indicateurs actifs et remplissages. Ils n’utilisent ni `Theme.action` ni `Theme.state`. Le liseré animé qui tourne autour de la capsule centrale reste rose, sauf pendant une notification : liseré et accents internes utilisent alors `Theme.state`.

Les compteurs ne changent pas de couleur selon leur quantité. Les icônes d’applications et favicons conservent naturellement leurs couleurs d’origine, car ce sont des contenus externes et non des accents d’interface.

Les capsules latérales ne changent pas de couleur selon leur état et conservent les accents fixes d’origine déclarés dans `Theme.js`. Les sept accents contextuels ci-dessus sont partagés avec leur widget central correspondant. `Pill.forceHovered` reproduit l’inversion visuelle du hover pendant que le widget central associé est ouvert. La top bar n’affiche aucune infobulle :

| Capsule | Token | Couleur |
|---|---|---|
| Applications | `Theme.sideApplications` | `#7dc4e4` |
| Updates | `Theme.sideUpdates` | `#f0c6c6` |
| Réseau | `Theme.sideNetwork` | `#ee99a0` |
| Bluetooth | `Theme.sideBluetooth` | `#8aadf4` |
| Système (CPU, RAM, GPU, disque) | `Theme.sideSystem` | `#c6a0f6` |
| Batterie | `Theme.sideBattery` | `#f4dbd6` |
| Volume | `Theme.sideVolume` | `#b7bdf8` |
| Luminosité | `Theme.sideBrightness` | `#eed49f` |
| Température météo, date, heure | `Theme.sideWeather` | `#f5bde6` |

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

Cette interpolation monotone est commune aux transformations entre workspaces, volume, luminosité, dictée, média, Wi-Fi, Bluetooth, updates, lanceur d’applications et onglets Chrome.

Ne pas réintroduire :

- `Easing.OutBack`, `SpringAnimation` ou une propriété `overshoot` ;
- une cible intermédiaire au-delà de la géométrie finale ;
- une séquence aller-retour pour simuler un rebond ;
- un état ou timer temporaire tel que `updateMorphGentle` / `updateMorphTimer`.

Les transitions secondaires suivent la même règle, avec une exception explicite
pour le rebond de sélection demandé par l’utilisateur. `SelectionBounce.qml`
anime uniquement les capsules latérales en état `hovered` (survol ou
`forceHovered`). Le rebond accompagne les couleurs existantes et reste actif
lors d’une sélection au clavier. Les workspaces, y compris les special
workspaces, ainsi que les lignes des lanceurs applications / onglets Chrome
ne rebondissent pas.

La capsule updates suit uniquement le survol ou l’ouverture de son sélecteur
sur le même écran. Une vérification, une installation, une attente de validation
ou un redémarrage requis ne forcent ni la couleur de sélection ni le rebond.
Ces états restent indiqués par l’icône et le contenu du sélecteur.

Le mouvement est centré sur la position au repos : `6px` vers le haut et `6px`
vers le bas. La montée jusqu’à `-6px` dure `300ms` en `OutQuad`, puis la chute
accélère jusqu’à `+6px` pendant `220ms` en `InQuad`. Le changement de direction
est immédiat en bas, comme un impact sur une surface dure ; seul le sommet
ralentit progressivement. La boucle dure `520ms` et traverse la position au
repos sans y marquer de pause. La désélection interrompt la
boucle et ramène l’élément à sa position initiale en `140ms`. Une resélection
interrompt ce retour et repart de la position courante. Seul le contenu visuel
bouge : les zones de clic et la géométrie de mise en page restent fixes. Les
animations sont arrêtées lorsque le composant est masqué ou désactivé.

Les pulses de scale sur les icônes volume et luminosité restent supprimés. Le
contenu central utilise une seule animation partagée, calculée depuis le widget
source et le widget destination ; chaque composant ne relance jamais sa propre
animation `presented`. Le rebond de sélection ne modifie pas cette transformation
ni les interpolations monotones de largeur et de hauteur.

### Transition de contenu à deux couches

Les composants source et destination restent rendus simultanément pendant une courte fenêtre. Leurs opacités et translations sont calculées depuis un unique `transitionProgress` de `0` à `1`; aucun composant ne possède son propre `Behavior on opacity` ou timer d’entrée.

Le conteneur, le clipping et la bordure restent persistants. Seuls les contenus se croisent à l’intérieur, comme dans une container transform. Une répétition du même mode sur le même moniteur ne redémarre pas la transition. En cas d’interruption, les opacités et offsets actuellement rendus des dix modes sont capturés dans des tables ; la nouvelle destination continue depuis sa valeur courante et toutes les autres couches encore visibles terminent leur fade au lieu de disparaître brutalement. Cette règle reste valable même pour une séquence très rapide A → B → C → D.

## 6. Animation contextuelle du contenu central

`StatusData` conserve les transactions des overlays. Chaque `Bar` pilote désormais
la transition depuis son mode réellement présenté vers son `targetMode`, avec
`Qt.callLater` pour regrouper les changements synchrones. Les états intermédiaires
`workspaces` produits par les booléens ne deviennent donc pas une transition
visible. Une notification peut masquer un overlay dont l’état continue à évoluer ;
sa fermeture révèle directement le mode sous-jacent encore actif sur ce moniteur.

Chaque `Bar` anime pendant les mêmes `360ms` que la géométrie :

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

## 7. Liseré d’activité rose / jaune

Le liseré apparaît lorsque `centerMorph.overlayVisible` est vrai, donc pour :

- volume ;
- panneau audio ;
- luminosité ;
- dictée vocale ;
- Wi-Fi ;
- Bluetooth ;
- média MPRIS ;
- lanceur d’applications ;
- onglets Chrome ;
- updates ;
- notifications.

Il disparaît uniquement quand la capsule redevient le widget des workspaces.

### Rendu actuel

Le liseré n’utilise ni `Canvas`, ni `Repeater` de petits rectangles, ni gradient conique. Le `Repeater` demandait jusqu’à plus de mille mises à jour QML par frame sur deux écrans ; le gradient conique était plus léger mais accélérait visuellement dans les coins parce qu’un angle constant ne correspond pas à une distance constante sur un rectangle.

La version actuelle utilise un unique `ShaderEffect` et `shaders/activity-border.frag` :

- shader Qt 6 compilé en `.qsb` par `quickshell.nix` avec `qtshadertools` ;
- rectangle arrondi de rayon extérieur `18px` ;
- anneau intérieur de `3px` calculé par signed-distance field ;
- position exacte sur le périmètre calculée avec les longueurs des quatre segments et des quatre quarts de cercle ;
- traînée couvrant `50 %` du périmètre ;
- couleur de tête `Theme.action` (`#ff33cc`), ou `Theme.state` (`#ffcc33`) pour les notifications, transmise par l’uniforme `trailColor` ;
- opacité `Math.pow(1 - behindHead / 0.5, 1.35)` ;
- phase de `0` à `1` en `1600ms`.

Les états `0` et `1` sont identiques et la coupure opaque-vers-transparent reste placée à la tête. La phase est le seul uniforme animé en continu ; la géométrie, la position sur le chemin, l’anticrénelage et le dégradé sont calculés en parallèle sur le GPU. La sortie du fragment shader est prémultipliée pour respecter le blending du scene graph Qt Quick. La couleur reste jaune jusqu’à la fin du fade de la notification sortante, puis retrouve le rose du widget sous-jacent, sans redémarrer la rotation.

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

- largeur minimale exacte requise par le contenu, plafonnée à `400px`, sauf
  pendant un speed test Wi-Fi où elle reste fixée à `400px` ;
- pendant un changement de largeur, les noms sont découpés par le viewport sans
  afficher de points de suspension transitoires ;
- hauteur `36px`, étendue à `94px` pendant un speed test ;
- compteur aligné sur une hauteur fixe de `18px` ;
- animation de roue verticale en `150ms` ;
- déplacement de `40px` hors du viewport découpé ;
- easing `InOutCubic`.

La roue ne se déclenche que pour une navigation volontaire (`j/k/h/l`, flèches, `g/G` pour le Wi-Fi). Elle ne doit pas tourner lors de l’ouverture, de la fermeture, d’un scan ou d’un changement de message.

### Services natifs et scans

Le Wi-Fi utilise exclusivement `Quickshell.Networking` : devices NetworkManager, réseaux, puissance, sécurité, états, scan et connexion PSK. Aucun helper `nmcli` ne doit être réintroduit.

Le Bluetooth utilise exclusivement `Quickshell.Bluetooth` : découverte BlueZ, appareils, appairage, connexion et déconnexion. Aucun helper `bluetoothctl` ne doit être réintroduit.

À l’ouverture, les modèles natifs déjà chargés s’affichent immédiatement. `WifiDevice.scannerEnabled` reste actif pendant toute la durée de vie du sélecteur, car Quickshell masque les réseaux inconnus dès que le scanner est désactivé. Le timer de rafraîchissement arrête uniquement le spinner ; la fermeture du sélecteur arrête réellement le scanner.

Un vrai spinner est réservé à :

- `r` pour un scan Wi-Fi explicite ;
- `t` pendant l’exécution explicite du client Ookla ;
- l’onglet Bluetooth `NEARBY`, via `BluetoothAdapter.discovering`.

Le speed test n’est jamais automatique. `t` étend la capsule vers le bas et lance `quickshell-speedtest`, wrapper du client officiel `ookla-speedtest`. Son flux JSON progressif met à jour en direct la phase (`PING`, `DOWNLOAD`, `UPLOAD`), la valeur courante, le pourcentage global monotone et une barre de progression, puis affiche le résultat final. Une fermeture du sélecteur interrompt tout le groupe de processus et un timeout de `90s` empêche tout processus bloqué.

### Couleurs d’état

- Wi-Fi : icône et point de connexion utilisent `Theme.sideNetwork` ;
- Bluetooth : icône, point de connexion et onglets `PAIRED` / `NEARBY` utilisent `Theme.sideBluetooth` ;
- tout appareil ou réseau non connecté reste gris ;
- cadenas Wi-Fi : même gris que le compteur (`#939ab7`) ;
- le liseré animé autour de la capsule reste rose, sauf pendant les notifications où il devient jaune vif.

## 11. Panneau audio et lanceurs

### Panneau audio

Le clic sur la capsule volume et `Super+R` appellent `topbar.toggleAudio` et
ouvrent `AudioSelector.qml` au centre, sur l’écran cible. L’en-tête affiche
l’icône audio, le titre `AUDIO` et le compteur `n OUT · n IN`, puis une seule page
affiche `OUTPUTS` et `MICROPHONE`, avec une coche sur les périphériques réellement utilisés.
Largeur limitée par le plafond commun des workspaces, hauteur adaptée jusqu’à
`398px`, puis défilement. Haut/bas ou
`j/k` naviguent, `Tab` change de section, `Enter` choisit sans fermer et `Esc`
ferme. Aucun volume par application ni barre de réglage supplémentaire.

Le panneau utilise `Theme.sideVolume`, les transitions communes de `360ms`, le
liseré et l’exclusivité des overlays. La dictée conserve sa priorité ; le panneau
ne prend pas le focus clavier pendant la dictée. Les touches volume et la molette
restent actives et ne remplacent pas un panneau audio ouvert par l’OSD volume.

La capsule latérale garde toujours `icône son + pourcentage + icône micro`, même
si la sortie est muette. Le micro est barré lorsqu’il est muet, normal sinon, et
grisé sans entrée disponible. La touche VIA `Mac Voice` du NuPhy Air60 V2
émet `XF86VoiceCommand` sous Linux et appelle `topbar.toggleMicrophoneMute`,
qui agit sur le micro par défaut uniquement.
Chaque action mute ou démute active l’inversion de couleur et le rebond de la
capsule audio sur l’écran focalisé pendant `2000ms`, comme l’indicateur volume.
Une nouvelle action relance ce délai. L’état muet seul n’entretient pas le rebond ;
à la fin du délai, la capsule revient au repos, sauf si elle est survolée ou si
son panneau/indicateur volume reste ouvert.
L’icône reflète aussi les changements externes et ne représente pas un
enregistrement en cours. Changer d’entrée ne modifie pas son état muet.

Les périphériques et leur état sont fournis par PipeWire natif dans Quickshell,
avec `PwObjectTracker` ; aucun helper Rust ni polling de `wpctl`. Une sélection
écrit `preferredDefaultAudioSink` ou `preferredDefaultAudioSource`, tandis que
les coches suivent les périphériques par défaut effectifs.

`system/wireplumber/release-on-hotplug.lua` libère le choix manuel de la direction
concernée quand les périphériques ou la disponibilité de leurs routes changent.
WirePlumber reprend alors ses priorités habituelles. Les changements de volume,
de mute ou les flux d’applications ne libèrent pas le choix. La désactivation de
`node.restore-default-targets` empêche seulement la restauration des anciens
choix : elle ne suffit pas à elle seule pour annuler une préférence courante.
Le test isolé est `lua system/wireplumber/release-on-hotplug_test.lua`, depuis la
racine du dépôt. Une validation matérielle doit couvrir casque filaire,
Bluetooth, HDMI, retrait de périphérique et touche micro du laptop.

### Applications

Le raccourci `Super+A` et le logo Nix à gauche ouvrent `AppLauncher.qml` dans la capsule centrale. Le lanceur utilise exclusivement `DesktopEntries.applications` et `DesktopEntry.execute()` : ne pas réintroduire Fuzzel ou une analyse périodique des fichiers `.desktop`.

Conventions :

- largeur souhaitée `480px`, limitée par le plafond commun des workspaces,
  hauteur `398px` et huit lignes visibles ;
- toutes les applications non marquées `NoDisplay` restent accessibles avec une icône issue du thème ;
- le catalogue normalisé est construit une seule fois, puis la recherche fuzzy s’effectue en mémoire ;
- le `ListView` virtualise les lignes pour ne charger que les icônes visibles ;
- haut/bas, `Ctrl+n/p`, `Ctrl+j/k`, PageUp/PageDown et molette naviguent ;
- l’icône de recherche, la sélection de texte et le point d’une application déjà ouverte utilisent `Theme.sideApplications` ;
- aucune flèche d’action n’est affichée sur la ligne sélectionnée ;
- `Enter` active la fenêtre ouverte la plus récemment utilisée, y compris depuis un autre workspace normal ou spécial, sinon lance l’application ;
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
- `Enter` active l’onglet avec TabCtl puis focalise explicitement sa fenêtre via Hyprland, y compris depuis un autre workspace normal ou spécial ; `Ctrl+W` ferme l’onglet, `Ctrl+R` recharge la liste et `Esc` ferme le widget ;
- clic gauche : activation ; clic droit : fermeture ;
- huit lignes complètes sont visibles et le `ListView` reste virtualisé ;
- l’extension TabCtl est installée manuellement depuis le Chrome Web Store ; seul le manifeste `tabctl_mediator.json` est géré par Home Manager, donc ne jamais exécuter `tabctl install` manuellement.

## 12. Volume et luminosité

- Largeur `280px`, hauteur `36px`.
- Aucun pourcentage dans le widget central.
- Timeout de visibilité : `2000ms`.
- Les touches multimédia et les molettes modifient le volume par pas de `5%`.
- La barre de progression anime sa largeur en `140ms`.
- Les valeurs volume utilisent directement `Quickshell.Services.Pipewire`, y compris les touches XF86 et le mute ; aucun `wpctl` ne doit être réintroduit.
- La luminosité passe par `quickshell-brightness` : `brightnessctl` pour la dalle interne, `ddcutil` pour un écran externe identifié par connecteur, modèle et numéro de série. Les touches ciblent le moniteur focalisé ; la molette cible celui de la barre. Pour un écran externe, les appuis sont regroupés jusqu’à une pause de 180 ms, avec conservation des inversions de sens et saturation à chaque pas. L’OSD affiche immédiatement la consigne dès qu’une valeur est connue, puis se recale sur la réponse. Le bus est mémorisé en RAM et invalidé lors d’un changement de moniteurs ; une génération permet d’ignorer les réponses antérieures au changement. La dernière valeur vérifiée est réutilisée pendant deux secondes, puis relue à la prochaine interaction. Une seule écriture vérifiée est effectuée par groupe d’appuis, sans polling DDC ni modification du pilote.
- Le volume utilise `Theme.sideVolume` pour son icône et son remplissage.
- La luminosité utilise `Theme.sideBrightness` pour son icône et son remplissage.
- Les barres de progression ne possèdent aucun curseur ou point blanc : seul le remplissage coloré indique le niveau.
- Chaque indicateur central apparaît uniquement sur le moniteur qui a reçu la touche ou le geste de molette.
- Hors plein écran, le volume et la luminosité restent dans `centerMorph` : le widget central précédent se transforme directement en indicateur, avec le même morphing et le même fondu croisé que les autres modes de la barre. Lorsqu'un workspace contient une fenêtre plein écran, un `LazyLoader` crée à la place une `PanelWindow` dédiée sur la couche Wayland native `Overlay`. La barre principale reste alors en permanence sur `Top` et ne peut jamais apparaître brièvement au début ou à la fin de l'OSD. La surface dédiée ignore les zones d'exclusion ; son contenu passe de `352px` à `280px` et descend de `8px` pendant `360ms`, puis joue le mouvement inverse à la fermeture.

## 13. Contrôles média MPRIS

Les touches média utilisent `Quickshell.Services.Mpris`, jamais un processus `playerctl`.

`StatusData.mprisPlayer` préfère le contrôleur D-Bus `playerctld`, qui conserve la notion de dernier lecteur actif lorsque plusieurs applications ou onglets publient MPRIS. En son absence, la sélection tombe sur le lecteur en cours de lecture, puis un lecteur en pause.

Les raccourcis Hyprland appellent les méthodes IPC `mediaPlayPause`, `mediaNext` et `mediaPrevious`. Chaque méthode vérifie les capacités du lecteur avant l’action.

La pause automatique liée à la dictée appartient à Voxtype via
`[audio] pause_media = true`. `StatusData` ne commande donc pas les lecteurs
MPRIS lors des changements d'état de la dictée : il se limite à afficher
l'état et la waveform. Voxtype mémorise les lecteurs réellement en lecture,
les met en pause pendant la dictée et les relance une fois la transcription et
la sortie terminées.

`NowPlayingIndicator.qml` ajuste sa largeur souhaitée au titre et à l'artiste entre `160px` et `480px`, puis la capsule applique le plafond commun des workspaces. Il affiche quatre petites barres d’égaliseur animées, puis le titre et l’artiste sur une seule ligne centrée au format `Titre • Artiste`, sans pochette, avec l’action play/pause à droite. Le texte utilise la même taille de `16px` que les capsules latérales et l’égaliseur garde une marge gauche de `15px`. Les barres sont jaunes et animées pendant la lecture, puis deviennent grises et restent basses en pause ; l’icône d’action play/pause reste rose. Le widget reste visible `4000ms` après une action média déclenchée par les touches Play/Pause, Suivant ou Précédent. Les signaux automatiques de changement de piste n'ouvrent jamais le widget, car les navigateurs et les applications de communication publient les vocaux et vidéos par le même protocole MPRIS que les lecteurs musicaux.

## 14. Exclusivité entre overlays

Un seul mode central peut être actif à la fois.

Lors de l’ouverture d’un overlay :

- fermer les lanceurs via `hideAppLauncher()` et `hideChromeTabs()` ;
- fermer Wi-Fi/Bluetooth via leurs fonctions `hide*`, jamais par mutation directe des booléens ;
- arrêter les timers volume/luminosité via `hideVolumeOverlay()` et `hideBrightnessOverlay()` ;
- fermer updates via `hideUpdateSelector()` ;
- résoudre et enregistrer le moniteur cible avant de rendre le nouvel overlay visible ;
- laisser les workspaces inchangés sur les autres écrans.

Le nettoyage Wi-Fi arrête le scanner, le timer de connexion, le speed test Ookla, le mot de passe et le réseau pending. Une génération identifie chaque speed test afin qu’une sortie tardive d’un processus annulé ne puisse jamais remplacer un résultat plus récent.

Une action Bluetooth native déjà lancée continue lorsque le sélecteur est masqué. Son timer et son message restent associés à l’action afin qu’une réouverture puisse afficher son état ; seule la découverte est arrêtée.

## 15. Raccourcis et contrôles

`Cmd` dans les demandes utilisateur correspond à `SUPER` dans Hyprland.

### Applications — `Super+A`

- saisir directement pour filtrer en fuzzy
- haut/bas, `Ctrl+n/p` ou `Ctrl+j/k` : navigation
- PageUp/PageDown : saut de huit résultats
- `Enter` : activer l’instance ouverte, y compris depuis un autre workspace normal ou spécial, sinon lancer
- `Ctrl+Enter` : lancer une nouvelle instance
- `Esc` : fermeture

### Onglets Chrome — `Super+;`

- saisir directement pour filtrer titre et URL
- haut/bas, `Ctrl+n/p` ou `Ctrl+j/k` : navigation
- PageUp/PageDown : saut de huit résultats
- `Enter` : activer l’onglet et focaliser sa fenêtre Chrome, y compris depuis un autre workspace normal ou spécial
- `Ctrl+W` : fermer l’onglet sélectionné
- `Ctrl+R` : recharger la liste
- clic droit : fermer l’onglet
- `Esc` : fermeture

### Wi-Fi — `Super+N`

- `j/l` ou bas/droite : suivant
- `k/h` ou haut/gauche : précédent
- `g/G` : début/fin
- `r` : rescan
- `t` : lancer ou relancer le speed test Ookla
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

Le widget central utilise `Theme.sideUpdates` pour les icônes, les états `CHECKING` / `AVAILABLE` et les points de chaque ligne. `UP TO DATE`, les dates et les états vides restent gris ; `ERROR` utilise `Theme.error` et ne doit jamais être présenté comme un système à jour. Le liseré animé autour de la capsule reste rose.

Le checker compare les anciens et nouveaux `flake.lock` comme JSON, sans analyser la sortie humaine de Nix. Il s'exécute au démarrage, toutes les 30 minutes et après une demande explicite ; son cache est invalidé immédiatement si `flake.nix` ou `flake.lock` change. L'installateur partage son verrou et restaure le lockfile précédent si le rebuild ou l'installation de la génération de démarrage échoue.

Le premier `Enter` remplace la liste par une capsule compacte de `36px` contenant uniquement le spinner Braille, le message d'étape et son état. Le wrapper réutilise le `flake.lock` candidat déjà calculé par le checker si l'empreinte du `flake.nix` et du lock d'origine correspond encore ; sinon il refait proprement `nix flake update`. Il construit ensuite avec `nh os build --diff never` et conserve le résultat par un out-link temporaire. À la fin du build, un helper lit les closures via `nix path-info --json --json-format 2` et Quickshell affiche une liste structurée compacte pouvant atteindre `750px`, avec les packages ajoutés, supprimés, modifiés, mis à niveau ou rétrogradés, dans cet ordre, et `ancienne version → nouvelle version` sur la même ligne. Un second `Enter` replie le centre à la hauteur de la barre et affiche la saisie Polkit sur une seule ligne. `run0` lance ensuite un helper immuable du Nix store qui réutilise le résultat déjà construit et l'enregistre avec l'action native `boot`, sans modifier ni redémarrer la session courante. L'état final `Update ready — reboot required` persiste dans `$XDG_CACHE_HOME/quickshell/top-bar/pending-reboot.json`, y compris si QuickShell est relancé, puis disparaît automatiquement lorsque `/run/current-system` correspond à la génération attendue. Chaque état mesure son contenu : les états compacts sont plafonnés à `280px` ou `360px`, tandis que les listes et la saisie Polkit demandent jusqu’à `480px`, toujours sous le plafond commun des workspaces. Cela évite à la fois le wrapper `pkexec env` de `nh` et le binaire `pkexec` brut du Nix store, qui n'est pas setuid. Aucune fenêtre Ghostty et aucun second build complet ne sont lancés.

Le processus appartient à `StatusData`, pas au composant visible. `q`, `Esc` ou un clic sur la capsule latérale ne font donc que replier l'interface ; l'update continue et un nouveau clic retrouve l'état compact ou le résumé existant. Pendant l'installation de la génération de démarrage, la liste structurée reste visible ; après succès, une capsule compacte demande le redémarrage. Une erreur de build reste dans la capsule compacte avec son message structuré ; une erreur après le diff conserve la liste avec un état d'erreur. `Enter` relance ensuite une nouvelle tentative.

Pendant `CHECKING`, `Enter` est ignoré afin de ne pas lancer l'installer contre le verrou du checker. Dans l'état compact `UP TO DATE`, `Enter` replie simplement le widget. Si un checker détient malgré tout le verrou au démarrage de l'installation, l'installer attend sa fin au lieu d'émettre une erreur transitoire persistante.

Dans la vue initiale, `C` lance le nettoyage natif `nh clean all`. Le processus partage le verrou des updates, utilise la stratégie d'élévation `run0` fournie par `nh` et affiche la demande Polkit dans la barre si elle est nécessaire. Pendant le nettoyage, une capsule compacte animée reste repliable avec `Esc`; la sortie très volumineuse de `nh` est conservée dans le journal mono-exécution `$XDG_CACHE_HOME/quickshell/top-bar/clean.log` plutôt que poussée ligne par ligne dans QML. En cas d'échec, seules ses 30 dernières lignes sont affichées. À la fin, la barre affiche l'espace réellement récupéré à partir de l'espace disponible avant/après, sans analyser une sortie privée ou instable de `nh`.

`StatusData` fournit aussi l'agent Polkit de la session avec `Quickshell.Services.Polkit`. Toute demande d'une autre application utilise le même formulaire central, sans stocker la réponse dans les arguments, l'environnement, les fichiers ou les logs. Une demande externe restaure l'overlay précédent lorsqu'elle se termine.

- `r` : vérification forcée
- premier `Enter` : démarre l'update et affiche la capsule compacte
- `j/k` : fait défiler la liste structurée des changements, sans sélection
- `Enter` sur la liste des changements : demande le mot de passe puis installe la prochaine génération de démarrage
- `Enter` après installation : ferme la capsule `REBOOT` ; après erreur : réessaie
- `q/Esc` : replie la capsule sans interrompre l'update

Ne pas tester `Enter` automatiquement : cela lance réellement `nix flake update`, `nh os build`, puis l'installation privilégiée de la génération de démarrage.

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
nix-instantiate --parse home_manager/hyprland/default.nix >/dev/null
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

## 18. Notifications éphémères

Quickshell est l’unique serveur `org.freedesktop.Notifications` configuré.
`NotificationData.qml` est instancié une seule fois dans `StatusData`.

Une seule notification est présentée, sur l’écran focalisé à la réception.
La suivante remplace la précédente, y compris les mises à jour d’un même ID.
Il n’y a ni cloche, ni historique, ni file, ni stockage de messages sur disque.
Les notifications reçues en plein écran sont expirées sans affichage ni rejeu.
Le passage en plein écran ou la disparition du moniteur ferme la carte courante.

Chaque nouvelle notification affichée joue directement `message-new-instant.oga`
du thème freedesktop (environ `1s`) avec `pw-play`, au volume `2.0` (200 %) et
avec le rôle `Notification`. C’est le son « Message instantané » choisi après
écoute : amplification directe du flux par `pw-play` (gain linéaire ×2, environ
`+6dB`), sans conversion ni étape FFmpeg. Le fichier original et le volume général
restent inchangés. Le lecteur et le son sont épinglés dans le Nix store. Respecter
le hint `suppress-sound` ; les notifications rejetées en plein écran restent
silencieuses. Il n’y a **aucun intervalle minimum**, ni file audio : chaque arrivée
lance son lecteur indépendant, même pendant un son précédent. Les mises à jour
d’une carte existante (même ID, image, texte) ne rejouent pas le son.

La capsule s’étend vers le bas, sous le plafond commun des workspaces. La carte
adapte sa largeur au nom d’application, au titre et au message : `FontMetrics`
mesure la plus longue ligne non repliée avec la police du champ correspondant,
puis ajoute les marges et l’avatar (`16 + 42 + 12 + texte + 16`). La largeur
souhaitée va de `160px` à `480px`, toujours plafonnée par les workspaces dans
`Bar.qml`. Les retours à la ligne explicites ne s’additionnent pas. Cette mesure
ne dépend jamais de la largeur animée ni du texte déjà replié. Les messages longs
reviennent à la ligne et les remplacements plus courts réduisent la capsule.
Un `Text` de mesure non rendu calcule la hauteur du message à sa largeur finale,
avec le plafond transmis par `Bar.qml` et les mêmes paramètres de texte que le
champ affiché. Les retours à la ligne temporaires pendant l’animation ne font
donc pas gonfler puis rétrécir la hauteur de la capsule.
La carte mesure entre `80px` et `180px` de haut et affiche une image ronde de `42px`,
l’application, le titre et quatre lignes de message maximum. L’image native
peut être la photo d’un contact Beeper si l’application la transmet ; sinon,
utiliser son icône, puis un glyphe de notification si celle-ci manque aussi.
Le texte est rendu en `PlainText` et utilise les tokens de `Theme.js`.
Le liseré tournant et les accents internes (dont la cloche de secours) utilisent
le jaune vif `Theme.state`, jamais le rose `Theme.action`. Les textes neutres et
les images/icônes fournies par les applications conservent leurs couleurs.

Le timer dure `360 + 3000ms` : ouverture commune puis trois secondes de lecture,
sans pause au survol. Il est relancé lors d’un remplacement. Échap ferme sans
attendre ce timer. Un clic invoque l’action native `default` lorsqu’elle existe.
La fermeture conserve brièvement l’objet avec `RetainableLock` pour terminer
le fade et afficher son image, puis libère l’objet après `360ms`.

La notification a priorité visuelle sur tous les autres modes, y compris la
dictée. Leurs états et opérations continuent ; à la fermeture, afficher le mode
encore actif, sans relancer un indicateur déjà expiré. Ne pas désactiver puis
réactiver les composants masqués : cela réinitialiserait leurs sélections.
`NotificationInputGuard.qml` intercepte leur saisie et restaure le champ focalisé.
Une notification seule ne demande jamais de focus clavier exclusif.

`topbar.dismissNotification` ferme la carte. Un bind Lua `auto_consuming` ne
consomme Échap que lorsqu’une carte est signalée par Quickshell ; autrement,
la touche est transmise normalement. La présence est synchronisée par `hyprctl
eval`, avec un bail de cinq secondes pour ne pas garder Échap capturé après un
crash. Dans le sous-mode Voxtype, fermer une notification ne doit ni annuler
l’enregistrement ni réinitialiser le sous-mode ; l’Échap suivant reprend le
comportement d’annulation habituel.

Tests de régression : `QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
QT_NO_XDG_DESKTOP_PORTAL=1 qs -p tests/tst_NotificationPopup.qml` depuis `top-bar/`
vérifie la largeur adaptative, les retours à la ligne, les plafonds, les textes
Unicode et l’indépendance par rapport à la largeur rendue. Ce test QtTest utilise
`qs`, qui embarque les plugins statiques Quickshell nécessaires à la carte.
`tests/tst_NotificationInputGuard.qml` avec `qmltestrunner`
vérifie le focus, la protection du texte et Échap. `tests/escape_test.lua` prend
le fichier `hyprland.lua` généré par Home Manager et vérifie les deux raccourcis
dans un environnement Lua simulé. Vérifier également avec `notify-send` la
réception native, les remplacements d’ID, l’action `default`, les images et
l’expiration ; une notification réelle Beeper valide les données qu’il fournit.

## 19. Calendrier météo

`Super+E` (`Cmd+E`) remplace le lancement de Zed par `topbar.toggleCalendar`.
Le clic sur la capsule température/date/heure appelle le même panneau sur son
moniteur. Un second clic/raccourci ou Échap ferme le calendrier. `Super+Q`
continue d’ouvrir la configuration dans Zed ; `Super+M` garde le special
workspace Agenda, indépendant de ce calendrier consultatif.

Le mode `calendar` appartient aux transitions communes et prend exactement
`WorkspaceSwitcher.expandedImplicitWidth`, sans plafond local de `480px` ni
constante copiée de `434px`. Sa hauteur suit le contenu : en-tête, noms des jours,
quatre à six semaines nécessaires au mois, puis pied de panneau. Chaque semaine
garde sept colonnes alignées et adapte sa hauteur : `24px` pour les numéros seuls,
`44px` avec une icône, `60px` avec les mini/maxi. Les semaines sont espacées de
`4px`. Le pied de panneau suit la dernière semaine avec `10px` de marge, puis
`10px` jusqu’au bas. Aucune semaine vide ni espace météo inutilisé n’est réservé.
La hauteur est calculée depuis les données, sans attendre une passe de layout
(y compris derrière une notification ou sur un autre écran). Elle reste
indépendante de la largeur et utilise l’animation commune de la capsule centrale.
Les cases hors du mois sont vides. Le mois et les jours sont en français,
du lundi au dimanche. Utiliser la couleur météo `Theme.sideWeather` pour les
contrôles, icônes météo, températures et aujourd’hui, les neutres habituels pour
le texte. Les icônes météo utilisent les glyphes monochromes d’`Ubuntu Nerd Font`,
jamais les emojis multicolores. Chaque jour couvert affiche son numéro, son
icône et les températures mini/maxi en °C (`12°/24°`). Aujourd’hui utilise un
fond neutre et un contour coloré pour garder aussi son icône dans l’accent météo.
Le liseré reste le rose d’activité commun ; seules les notifications le rendent jaune.

Il n’y a pas de boutons de navigation souris dans l’en-tête : le titre utilise
toute la largeur disponible. H/L et les flèches gauche/droite (ou Page Up/Down)
changent le mois. Home et Entrée (y compris le pavé numérique) rétablissent le
mois courant avec aujourd’hui surligné, sans fermer.
Chaque nouvelle ouverture repart sur ce mois ; le passage derrière une
notification, la dictée ou une demande Polkit conserve le mois consulté.
Le passage à minuit suit le nouveau jour/mois tant que l’utilisateur n’a pas
navigué vers un autre mois. Il n’y a aucune action sur les cases, aucun événement
d’agenda, ni infobulle. Le focus et les clics masqués sont protégés par le guard
des notifications ; la dictée garde sa priorité. Une disparition du moniteur
cible ferme le calendrier.

L’outil Rust `quickshell-weather`, dans `tools/quickshell/weather/` et empaqueté
par `packages/quickshell/weather.nix`, remplace le wrapper `wttrbar`. Il récupère
la localisation IP automatique via `https://fwd.gr/api/tools/ip` (Cloudflare), puis une température
actuelle et 31 jours passés / jusqu’à 16 jours de prévision chez Open-Meteo.
Pas de compte, clé API, scan Wi-Fi ou service système supplémentaire. Conserver
le choix IPv4/IPv6 automatique de curl : ces adresses peuvent être localisées
différemment. Seuls ville et coordonnées sont conservées, pas l’IP ni les autres
métadonnées réseau/client renvoyées par fwd.gr. Le changement de fournisseur
ne modifie pas le protocole/cache v2 ; un cache existant reste utilisable en cas d’échec.
Il fournit des codes météo et températures mini/maxi quotidiens, pas les conditions de l’heure courante
répétées dans chaque case. Les jours passés utilisent des données de modèle
archivées et ne sont pas présentés comme des observations mesurées. Les dates
restent des clés ISO locales sans conversion UTC. Code inconnu ou nul : pas
d’icône. Mini/maxi incomplets : pas de température inventée. Date hors couverture :
numéro seul, sans tiret ni météo inventée.

Un seul `WeatherData` fournit température et calendrier à tous les écrans.
Actualiser au démarrage, chaque heure et à l’ouverture si les données sont
périmées ; ne jamais lancer une requête par jour ou écran. L’outil émet le cache
valide immédiatement puis le résultat actualisé en JSON Lines. Le cache est
écrit atomiquement dans `quickshell/weather/v2.json`, conservé en cas d’échec et
rejeté au-delà de 24 heures ;
l’interface applique aussi cette limite, même si aucun nouveau résultat n’arrive.
Afficher la ville, Open-Meteo et l’heure de mise à jour/cache dans le pied de
panneau. Sans données utilisables, conserver tout le calendrier et afficher `--°`
dans la barre. La géolocalisation IP peut être erronée même en fibre, et peut
être affectée par un VPN. Ne pas confondre ville estimée et position physique.

Tests : `tst_CalendarPanel.qml` avec `qmltestrunner` vérifie la grille, les années
bissextiles, les dates locales, les icônes/couleurs, les mini/maxi, la navigation
clavier (dont H/L/Entrée), l’absence de boutons et la hauteur ajustée aux semaines
et aux changements de données météo, sans variation liée à la largeur.
`QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1
qs -p tests/tst_WeatherData.qml` depuis `top-bar/` vérifie température nulle/zéro,
cache, expiration et erreurs. Les tests Rust du dossier de l’outil vérifient la
validation, l’horizon demandé et la cohérence localisation/cache hors ligne.

## 20. Règle finale pour une future IA

Avant toute modification visuelle, identifier clairement :

1. la géométrie qui doit bouger ;
2. le contenu qui doit suivre cette géométrie ;
3. le moniteur qui reçoit le rendu et le clavier ;
4. les autres écrans qui doivent conserver leurs workspaces sans reproduire l’animation ;
5. les limites physiques imposées par les modules latéraux ;
6. la restauration de l’état Hyprland après fermeture.

Tester l’ouverture, le milieu du mouvement, l’arrivée monotone et la fermeture. Vérifier image par image que la géométrie ne franchit jamais sa cible ; une capture finale seule ne suffit pas pour valider une animation.
