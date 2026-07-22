# Guide visuel et conventions d’animation — barre Quickshell

Ce document décrit les décisions visuelles, les conventions d’animation et les pièges déjà rencontrés pour la barre située dans le dossier parent. Il est destiné en priorité à une future IA qui devra modifier le widget sans casser sa cohérence.

## 1. Intention générale

La barre doit donner l’impression d’être un seul système animé, pas une collection de popups indépendants.

Principes fondamentaux :

- La capsule centrale est un objet unique qui **se transforme** entre workspaces, volume, luminosité, Wi-Fi, Bluetooth et mises à jour.
- Les changements de taille utilisent un rebond court et visible.
- Le contenu change instantanément : **pas de fondu entre les widgets**.
- Une transformation doit entraîner son contenu avec elle. Les éléments ne doivent pas sembler flotter indépendamment de leur capsule.
- Les indicateurs temporaires sont visibles sur tous les écrans, mais un seul écran reçoit le focus clavier.
- Le style reste Catppuccin sombre, avec un accent rose néon commun aux workspaces et au liseré d’activité.

## 2. Architecture à préserver

### Fichiers principaux

- `../shell.qml` : instancie un `StatusData` partagé et un `Bar` par écran.
- `../StatusData.qml` : source d’état globale, processus externes, timers, IPC et exclusivité entre overlays.
- `../Bar.qml` : géométrie de la barre, capsule centrale, animations globales et liseré d’activité.
- `../components/WorkspaceSwitcher.qml` : workspaces normaux et slot des special workspaces.
- `../components/VolumeIndicator.qml` / `BrightnessIndicator.qml` : indicateurs temporaires.
- `../components/WifiSelector.qml` / `BluetoothSelector.qml` : sélecteurs clavier.
- `../components/UpdateSelector.qml` : liste des mises à jour.
- `../components/Pill.qml` : capsule générique des modules latéraux.
- `../scripts/` : implémentations maintenues des helpers locaux Wi-Fi, Bluetooth et statistiques.
- `../../helpers/` : paquets Nix optimisés et nommés pour Quickshell.

### État partagé, rendu multi-écran

`StatusData` est unique pour toute la session. Chaque écran possède son propre `Bar`, mais tous lisent le même état.

Conséquences :

- Wi-Fi, Bluetooth, volume, luminosité et updates apparaissent sur **tous les écrans**.
- Les propriétés `wifiTargetMonitor`, `bluetoothTargetMonitor` et `updateTargetMonitor` désignent uniquement l’écran qui reçoit le focus clavier.
- Ne jamais limiter l’affichage au moniteur ciblé. Limiter uniquement `enabled` et `WlrLayershell.keyboardFocus`.

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
| Largeur updates | `480px` |
| Hauteur d’une ligne update | `30px` |

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

Couleurs de référence :

| Usage | Couleur |
|---|---|
| Fond principal | `#181926` |
| Surface secondaire | `#363a4f` |
| Texte principal | `#cad3f5` |
| Texte secondaire / compteurs / cadenas | `#939ab7` |
| Rose néon workspaces et liseré | `#ff33cc` |
| Vert connecté / succès | `#a6da95` |
| Bleu Bluetooth | `#8aadf4` |
| Rouge/rose Wi-Fi | `#ee99a0` |
| Jaune luminosité / vérification | `#eed49f` |
| Mauve secondaire | `#c6a0f6` |
| Erreur | `#ed8796` |

Police : `Ubuntu Nerd Font`.

Les libellés importants sont en gras. Le nom d’un special workspace utilise `Font.Black`.

## 5. Contrat d’animation de la capsule centrale

### Transformation générale

Dans `Bar.qml` :

- durée de largeur : `300ms`
- easing : `Easing.OutBack`
- overshoot normal : `5.5`
- durée de hauteur : `300ms`
- overshoot de hauteur : `1.8`

Le gros overshoot `5.5` donne le caractère très marqué demandé pour les transformations compactes.

### Cas particulier du widget update

L’écran interne ne laisse que peu d’espace entre le widget update et les modules latéraux. Un overshoot horizontal de `5.5` faisait temporairement recouvrir les modules de gauche et de droite.

Pendant une transition impliquant les updates :

- `StatusData.updateMorphGentle` est activé **avant** de modifier `updateSelectorVisible` ;
- la largeur utilise toujours `OutBack`, mais avec un overshoot contrôlé de `1.8` ;
- la durée reste `300ms`, identique à la hauteur ;
- `updateMorphTimer` libère ce mode après `360ms`.

L’ordre des mutations est important. Si `updateMorphGentle` est activé après `updateSelectorVisible`, l’animation peut démarrer avec l’overshoot `5.5` et recouvrir le reste de la barre.

### Pas de fade entre contenus

Les opacités des composants changent instantanément. Ne pas réintroduire de `Behavior on opacity` entre workspaces et overlays.

Le rebond provient de la géométrie, pas d’un fondu.

## 6. Animation du contenu update

Tout le contenu update doit participer :

- icône ;
- titre ;
- compteur ;
- séparateur ;
- noms des inputs ;
- dates.

`UpdateSelector.qml` utilise un bloc `animatedContent` avec `contentOffset` :

- départ à `-18px` ;
- arrivée à `0px` ;
- durée `300ms` ;
- `Easing.OutBack` ;
- overshoot `1.8`.

Le contenu commence donc légèrement au-dessus, descend dans le même sens que l’ouverture du widget, dépasse légèrement sa position finale, puis remonte pour se stabiliser.

La liste est placée dans un viewport découpé. Les lignes gardent toujours leur espacement de `30px` et sont révélées progressivement par la croissance du widget.

À ne pas refaire :

- espacement négatif entre les lignes ; cela superpose les textes ;
- faire remonter la liste depuis le bas ; le mouvement paraît opposé à l’ouverture ;
- animer seulement la liste en laissant le header immobile.

## 7. Liseré rose d’activité

Le liseré apparaît lorsque `centerMorph.overlayVisible` est vrai, donc pour :

- volume ;
- luminosité ;
- Wi-Fi ;
- Bluetooth ;
- updates.

Il disparaît uniquement quand la capsule redevient le widget des workspaces.

### Rendu actuel

Le liseré n’utilise pas un `Canvas` avec un dash animé. Cette approche produisait des disparitions et des saccades sur certaines portions du contour.

La version stable utilise :

- un chemin mathématique de rectangle arrondi ;
- `220` petits points de `3.5px` ;
- un segment couvrant `50 %` du périmètre ;
- couleur `#ff33cc` ;
- une opacité arrière progressive : `Math.pow(1 - trailPosition, 1.35)` ;
- un `FrameAnimation` synchronisé sur les frames ;
- une phase qui augmente continuellement avec `phase += delta / 1.6`.

La phase n’est jamais remise à zéro et n’utilise pas de boucle `NumberAnimation`. Il ne doit donc y avoir ni pause, ni redémarrage visible, ni notion perceptible de « tour ».

Le point de tête reste opaque ; l’arrière forme une traînée dégradée sans coupure nette.

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

Quand la capsule change de largeur, l’espacement entre les slots dépend de la largeur disponible. Les icônes participent donc au rebond au lieu de rester figées au centre.

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

### Cache et scans

À l’ouverture :

- afficher immédiatement le cache ;
- actualiser silencieusement en arrière-plan ;
- ne pas afficher un spinner pour un simple rechargement.

Un vrai spinner est réservé à :

- `r` pour un scan explicite ;
- l’onglet Bluetooth `NEARBY`.

### Couleurs d’état

- connecté : point vert `#a6da95` ;
- Bluetooth appairé mais déconnecté : bleu `#8aadf4` ;
- Bluetooth non appairé : gris ;
- cadenas Wi-Fi : même gris que le compteur (`#939ab7`).

## 11. Volume et luminosité

- Largeur `280px`, hauteur `36px`.
- Aucun pourcentage dans le widget central.
- Timeout de visibilité : `2000ms`.
- La barre de progression anime sa largeur en `140ms`.
- Les valeurs volume et luminosité peuvent être modifiées depuis leurs modules latéraux, mais l’indicateur central est partagé sur tous les écrans.

## 12. Exclusivité entre overlays

Un seul mode central peut être actif à la fois.

Lors de l’ouverture d’un overlay :

- fermer Wi-Fi/Bluetooth si nécessaire ;
- arrêter les timers volume/luminosité correspondants ;
- fermer updates via `hideUpdateSelector()` afin de conserver la convention `updateMorphGentle` ;
- ne pas affecter le rendu multi-écran.

Éviter les mutations directes de `updateSelectorVisible = false` pendant une autre transition. Passer par `hideUpdateSelector()`.

## 13. Raccourcis et contrôles

`Cmd` dans les demandes utilisateur correspond à `SUPER` dans Hyprland.

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

## 14. Pièges connus

1. **Animer la hauteur du `PanelWindow`** : provoque un glitch vertical du reste de la barre.
2. **Overshoot update à `5.5`** : recouvre les modules latéraux sur l’écran interne.
3. **Déclencher le mode doux trop tard** : l’animation capture le mauvais overshoot.
4. **Canvas + line dash animé** : le liseré peut disparaître ou sauter selon sa position.
5. **Boucle `NumberAnimation` pour le liseré** : crée une notion de fin de tour.
6. **Espacement négatif des lignes update** : superpose les textes.
7. **Liste update montant depuis le bas** : direction visuellement incohérente.
8. **Fade entre widgets** : contraire à la convention actuelle ; les contenus changent instantanément.
9. **Focus clavier sur tous les panels** : plusieurs surfaces se disputent le clavier.
10. **Rendu uniquement sur le moniteur ciblé** : contraire à la convention multi-écran.
11. **Mot de passe Wi-Fi dans les arguments de commande** : interdit ; utiliser stdin via `scripts/wifi-connect-password.sh`.
12. **Oublier de restaurer la bordure Hyprland** : laisse les fenêtres avec une bordure grise.

## 15. Procédure de validation

### Vérification QML rapide

```bash
timeout --signal=TERM 5s qs --no-color \
  -p "$PWD/home_manager/hyprland/quickshell/top-bar"
```

Le code doit afficher `Configuration Loaded` sans erreur QML. L’avertissement de portail `org.quickshell` est connu et non bloquant.

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
```

### Invariants à contrôler après une animation

```bash
hyprctl -j monitors | jq 'map({name,reserved})'
hyprctl getoption general:col.active_border -j
```

La réserve supérieure doit rester `[0,46,0,0]`. Hors overlay, la bordure active doit être revenue à `ff33ff33`.

## 16. Règle finale pour une future IA

Avant toute modification visuelle, identifier clairement :

1. la géométrie qui doit bouger ;
2. le contenu qui doit suivre cette géométrie ;
3. le moniteur qui reçoit le clavier ;
4. les autres écrans qui doivent reproduire l’animation ;
5. les limites physiques imposées par les modules latéraux ;
6. la restauration de l’état Hyprland après fermeture.

Tester l’ouverture, le milieu du mouvement, l’overshoot et la fermeture. Une capture finale seule ne suffit pas pour valider une animation.
