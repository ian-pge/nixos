# Liquid Glass — fonds des widgets Quickshell

Plugin local C++ / GLSL pour Hyprland 0.56.2, accompagné d'un module Qt pour
Quickshell. Il traite les fonds des capsules
et du panneau central de la barre Quickshell. Les textes, icônes, actions et
animations restent dessinés par Quickshell. Aucune interaction entre bulles
n'est ajoutée et Hyprlock conserve son rendu précédent.

## Visualiser la forme en 3D

Le dossier [`viewer/`](viewer/README.md) contient un visualiseur Three.js
indépendant, avec rotation, zoom, coupe centrale, maillage et comparaison du
coussin actuel avec les profils précédents. Depuis la racine : `nix develop .#threejs`, puis
`cd tools/liquid-glass/viewer`, `npm ci --ignore-scripts` et `npm run dev`.
Ouvrir <http://127.0.0.1:5173>. La hauteur de visualisation est explicitement
mise à l'échelle ; le mode ×1 montre les valeurs du champ, pas des millimètres.
Aucun réglage du visualiseur ne modifie la barre ni le shader.

## Fonctionnement

Le plugin intervient juste avant le dessin de la surface `quickshell-top-bar`.
Il conserve l'image du bureau à cet instant (fenêtres et vidéos comprises),
dessine le contenu de Quickshell dans un framebuffer transparent et utilise
les formes exactes transmises par les composants `GlassShape`. Le contour de
chaque rectangle arrondi est calculé directement à la résolution de l'écran ;
le relief intérieur du coussin est échantillonné dans un champ GPU mis en cache.
Le shader réfracte le fond puis compose les textes/icônes originaux par-dessus.
Les différentes capsules restent indépendantes ; la zone vide de la grande
surface de la barre reste transparente et ne change pas de géométrie.

Depuis la 0.5.0, la surface est le **dôme coussin validé dans le visualiseur**
(`viewer/src/cushion.ts`). Une application harmonique du disque vers le
rectangle arrondi porte une calotte elliptique. Les petits rayons restent au
contour, mais leur influence s'atténue vers le sommet : le bombé n'entretient
plus les crêtes concentrées du galet précédent. Il ne force plus des épaules
de même hauteur à distance égale du bord. Le contour extérieur, les dimensions,
les rayons et les zones cliquables ne changent pas.
Une même surface bombée détermine normales, déformation et épaisseur virtuelle.
La hauteur maximale et la déformation bornée à 36 pixels logiques (indice 1,5)
sont conservées ; le fumé, le flou et les teintes de sélection ne changent pas.

`src/cushion-field.hpp` calcule les mêmes 96 coefficients de Fourier à partir
des mêmes 2048 échantillons du contour que le visualiseur. `cushion-field.vert`
évalue positions et dérivées sur un maillage adapté aux coins, uniquement lors
de la génération du champ. Le cache commun `src/profile-field.hpp` conserve
un quart symétrique par forme dans une texture array RGBA16F. On y stocke le
carré de la hauteur normalisée et son demi-gradient négatif : leur interpolation
est plus fidèle près du bord que celle de normales déjà normalisées. Le dessin
final retrouve la hauteur par une racine et en déduit la normale du même relief.

La résolution est une puissance de deux entre 256 et 1024 pour les rayons usuels.
Elle peut atteindre 2048 pour les coins exceptionnellement serrés (par exemple
1 px sur un panneau de 480×398), afin de limiter l'erreur de réfraction à moins
d'un pixel. Sa borne haute est conservée jusqu'à la libération de la surface.
La clé de cache contient le rapport largeur/hauteur et le rayon normalisés,
pas la position, le fond ni le contenu. Déplacement et rebond uniforme ne
recalculent donc pas ce champ. Le contour garde son anticrénelage natif ; seul
son extrême bord utilise la normale limite verticale. L'intérieur suit le
coussin jusqu'au bord, sans réutiliser la bande du galet. Aucun maillage dense
n'est redessiné à chaque mouvement du fond.

Le galet 0.4.0 est archivé dans `pebble.frag`, `pebble-field.*` et
`src/pebble-field.hpp`, et le profil parabolique 0.2.5 dans `previous.frag`,
pour les comparaisons et tests ; ils ne sont plus le matériau des widgets.

Le reflet synthétique de Fresnel et le contre-bord sombre sont supprimés :
aucun liseré blanc ni assombrissement de contour n'est ajouté, y compris
dans le chemin raster de repli. La courbure continue à déformer le fond réel,
avec le même fumé et sans retour de l'ancien contour tournant.
Depuis la 0.2.4, le fond reçoit un flou gaussien modéré et uniforme avant
la réfraction (sigma voisin de 3 pixels logiques). Deux passes séparables à
demi-résolution, avec cinq lectures bilinéaires chacune, sont mises en cache
avec le fond. Le petit filtre final de réfraction reste inchangé :
**aucun adoucissement variable selon l'angle** n'a été ajouté. Les textes,
les icônes et les pixels hors du verre ne passent pas dans le flou.
Ce matériau reste une approximation de lentille mince, sans ray tracing ni
reflet capturé d'un environnement 3D.

Le fumé suit une atténuation exponentielle inspirée de Beer-Lambert : les
parties virtuellement épaisses sont plus sombres. Aux réglages de référence,
le mélange charbon représente environ 62–75 %, sans assombrir les textes.
Le plugin restaure les états de rendu via Hyprland
pour conserver la cohérence de ses caches, notamment pour le curseur logiciel.

### Géométrie synchronisée et compatibilité

Le module `Local.LiquidGlass` lit les formes pendant `beforeSynchronizing`,
quand Qt bloque le thread GUI. Il envoie des coordonnées fixes à 1/256 de pixel
logique sur la même connexion Wayland que la surface, avant son buffer.
Le serveur capture la géométrie lors de la mise en file du buffer puis la
valide lorsque les callbacks de CE buffer sont appliqués : les fences GPU
ne peuvent pas lui faire utiliser la forme d'une image suivante.
Les régions d'entrée et d'opacité Wayland ne sont jamais utilisées comme
canal de métadonnées. Aucun processus IPC n'est lancé à chaque frame.

Une transformation non prise en charge, une version Qt différente, ou une
frame sans marqueur fiable conserve le chemin raster hérité de la 0.1.5 comme repli. Celui-ci
déduit toujours son contour de l'alpha, avec sa carte à demi-résolution.
Ce repli conserve l'ancien relief : sans géométrie fiable, il ne prétend pas
reproduire le coussin exact. Les widgets Quickshell ordinaires utilisent les
métadonnées et le nouveau profil.
`analyticFrames` et `rasterFrames` dans `hyprctl liquidglass` distinguent ces
deux chemins. Les capsules analytiques restent indépendantes même si leurs
rectangles de calcul se chevauchent.
Pour tester le repli sans métadonnées, lancer Quickshell ou le test imbriqué
avec `LIQUID_GLASS_DISABLE_GEOMETRY=1` ; le chemin raster garde le même réglage de fumé.

Le module Qt accède au `wl_surface` par une **interface native privée de Qt**.
Il est compilé avec la version Nix de Quickshell et vérifie `qVersion()` avant
de l'utiliser. Cette dépendance doit être revalidée après mise à jour de Qt.
Le transport `libliquid-glass-wire` est séparé du plugin de rendu et garde une
durée de vie égale à celle du compositeur : ses quelques handlers restent
valides pour les requêtes en vol après déchargement du plugin. Le global
Wayland est retiré, les écouteurs Hyprland déconnectés ; le transport restant
ne fait aucun rendu et ne possède aucune ressource GPU. Les données sont
libérées à la destruction des surfaces et du display.

Références Qt : [synchronisation du scene graph](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html)
et [extensions Wayland](https://doc.qt.io/qt-6/qwaylandclientextension.html).

### Réglages du matériau et coût

Dans `shaders/analytic.frag`, `IOR = 1.50` règle l'indice optique et
`ABSORPTION = 1.40` le fumé. L'épaisseur relative varie de 0,70 à 1 selon
la hauteur de la surface. Ces épaisseurs ne sont pas des mesures
physiques en millimètres. Modifier la force de réfraction exige aussi de
vérifier la marge d'échantillonnage de 48 pixels dans `plugin.cpp`.
Le pas de flou `1.75F * monitor->m_scale` dans `renderGlass` règle son intensité
indépendamment du fumé et de la courbure ; une hausse exige de vérifier la marge.

Le chemin avec géométrie exacte n'utilise plus la carte de distance raster.
Le dessin final nécessite huit lectures de texture par pixel de verre
(sept en 0.2.5, avant le champ de normales ; douze en 0.1.5).
Les capsules sont regroupées dans un dessin instancié :
le shader ne parcourt pas toute la surface transparente de la barre.
Les pixels de premier plan totalement opaques
sortent immédiatement, sans calculer un fond invisible. Il n'y a ni
suréchantillonnage, ni rayon volumétrique, ni texture de reflet supplémentaire.

Le flou ajoute bien un coût GPU : deux dessins à demi-résolution lorsque le
fond est recapturé, aucun recalcul quand il est réutilisé. `blurUpdates` dans
`hyprctl liquidglass` doit suivre `backgroundCopies`. Les deux textures de flou
sont libérées avec les autres ressources lors de la désactivation du verre.
Sur RTX 4000 Ada, le microbenchmark offscreen 5120×900 mesure environ
0,036–0,048 ms supplémentaires par recalcul (deux passes + dessin final),
avec un coût du dessin final seul comparable lorsque le flou est en cache.
Cela n'inclut pas le rendu QML ni la capture du fond, dont la marge est de
48 px ; ce n'est donc pas une mesure du coût total du compositeur.

Historique : sur la même RTX 4000 Ada, le benchmark 0.4.0 / 0.2.5
mesure le dessin seul à environ 0,006 / 0,0045 ms (capsules), 0,020 / 0,0136 ms
(panneau) et 0,10–0,12 / 0,078–0,091 ms (forte couverture). Avec le flou
renouvelé à chaque dessin, la hausse est de l'ordre de 5–22 % sur ces scènes.
Pour le coussin 0.5.0 / galet 0.4.0, le dessin en cache reste comparable :
environ 0,006 ms pour les capsules, 0,020 ms pour le panneau et 0,104–0,127 ms
pour la forte couverture. Pas de régression des ratios médians appariés dans
ces six cas ; avec le flou renouvelé, les écarts mesurés vont de −0,33 à +0,55 %.
Ce n'est pas une promesse de coût strictement nul ou de résultat identique
sur tous les GPU. La génération d'un champ coussin sur défaut de cache coûte
environ 1,73 ms CPU et 0,050 ms GPU, contre 0,69 / 0,018 ms pour le galet.
Ces mesures hors écran ne sont pas le coût total de Hyprland. Les champs
occupent `8 × résolution² × capacité` octets par surface (capacité arrondie
à la puissance de deux, maximum 64 couches) ; ils sont libérés à la destruction
de la surface, à la désactivation et au déchargement du plugin.

Référence du fumé : [transmission de Beer-Lambert](https://pbr-book.org/4ed/Volume_Scattering/Transmittance).

Le rendu reste sur le GPU. Le contenu Quickshell et le masque de repli sont mis en cache
entre les commits et les changements de géométrie, d'échelle ou d'opacité.
Le fond est recadré sur l'ensemble des capsules connues, avec
une marge de 48 pixels logiques pour la réfraction et le flou. Seule cette
zone est rafraîchie avant de recopier le fond : les pixels contenant le verre
de la frame précédente ne sont jamais rééchantillonnés. Les anciennes positions
sont également endommagées lors d'un déplacement ou d'une disparition.

Un changement éloigné de cette zone ne recopie pas son fond. Les réparations
liées à l'âge des buffers utilisent le fond propre en cache et le dessin final
respecte la région endommagée. Les optimisations d'occlusion de Hyprland restent
actives sur les écrans non pivotés ; les écrans pivotés gardent le chemin
conservateur plein écran. Aucun timer ni rendu continu au repos n'est ajouté.

Limite volontaire : le fond est copié dans le rectangle englobant les capsules,
pas dans un atlas séparé par bulle. Le repli raster suit encore la surface
layer-shell complète. Le framebuffer du contenu natif garde aussi la
taille de l'écran pour préserver la projection de Hyprland, mais son contenu
n'est plus redessiné à chaque frame du fond. Un atlas plus fin et la mesure
du temps GPU global restent des optimisations/mesures distinctes du benchmark
du shader de matériau ci-dessous.

Le chargement est déclaré dans Home Manager. `GlassState.qml` conserve les fonds
opaques si le plugin n'est pas disponible et les restaure lors de son retrait.
Le code vérifie l'ABI de Hyprland avant de s'installer et refuse un autre moteur
que le renderer OpenGL. Il utilise un hook interne de `renderLayer` : aucune
modification des sources de Hyprland, mais compatibilité à revalider après une
mise à jour. Ce matériau est notre approximation visuelle, pas le code d'Apple.

## Construction et activation

Depuis la racine du dépôt :

```bash
nix build .#liquidGlass
sudo nixos-rebuild switch --flake .#nixos
hyprctl liquidglass
```

La dernière commande indique l'état, le nombre de surfaces et de passes de
rendu, les mises à jour du contenu et les pixels copiés/composés. `profile` vaut
`"cushion"` et `profileUpdates` compte les reconstructions du champ de forme ;
ce compteur doit rester stable quand seul le fond ou la position change.
`referencePixels`
est le nombre de pixels qu'aurait traité une copie plein écran pour ces mêmes
passes : ce sont des compteurs de travail, **pas une mesure de temps GPU**.
`hyprctl liquidglass reset-stats` remet ces compteurs à zéro sans changer le rendu.
Si le plugin ne se charge pas, consulter `hyprctl configerrors`.

### Retour immédiat aux fonds opaques

```bash
hyprctl liquidglass disable
# Pour réactiver le verre :
hyprctl liquidglass enable
```

La désactivation ne redémarre ni Hyprland ni Quickshell. Elle rend la main au
dessin natif, rétablit les fonds opaques et libère les textures en cache à la
frame suivante. Elle ne restaure pas les anciens choix indépendants du verre
(liseré tournant supprimé, teinte légère des boutons conservée).

Pour un retour permanent, mettre `enableLiquidGlass = false;` dans
`home_manager/hyprland/default.nix`, puis reconstruire la configuration NixOS.
Le plugin ne sera plus chargé au démarrage ; utiliser la commande `disable`
pour la session courante. On peut également le décharger avec
`hyprctl plugin unload CHEMIN_DU_PLUGIN` ; le repli opaque reste automatique.

## Activation

Depuis ce dossier, autoriser une fois l'environnement direnv :

```bash
direnv allow
```

Direnv charge ensuite automatiquement les outils à l'entrée dans ce dossier.
Son `.envrc` sélectionne l'environnement C++ ; les autres projets de `tools/`
conservent l'environnement Rust défini par le `.envrc` parent.

Pour ouvrir manuellement le même environnement depuis la racine du dépôt :

```bash
nix develop .#cpp
```

Le shell de développement ne demande aucune installation globale. Les versions
proviennent du `flake.lock` du dépôt ; seule l'activation persistante du plugin nécessite
le rebuild indiqué ci-dessus.

## Outils et dépendances

- GCC et les dépendances de développement du même paquet Hyprland que le système.
- CMake, Ninja et pkg-config pour la compilation.
- clangd, clang-format et clang-tidy pour l'assistance C++, le formatage et l'analyse.
- glslang (`glslangValidator`) pour la validation des shaders GLSL.

Le shell reprend explicitement `pkgs.hyprland.stdenv` pour éviter un mélange de
compilateurs avec Hyprland. `CLANGD_FLAGS` autorise clangd à interroger uniquement
ce compilateur pour retrouver ses en-têtes système. Cela aligne l'environnement
sur le paquet Nix ; après
une mise à jour, il faut également vérifier que la session Hyprland en cours
utilise bien cette version avant d'y charger un plugin.

## Compilation locale et tests

```bash
cmake -S . -B build -G Ninja
cmake --build build
ctest --test-dir build --output-on-failure
```

`CMAKE_EXPORT_COMPILE_COMMANDS=ON` est défini par le shell. CMake génère ainsi
`build/compile_commands.json`, utilisable par clangd pour connaître les options
et chemins d'inclusion du projet. Pour vérifier explicitement un fichier :

```bash
clangd --check=src/plugin.cpp --compile-commands-dir=build
```

La validation GLSL peut se lancer avec `glslangValidator fichier.frag`.

Depuis la racine :

```bash
glass_plugin=$(nix build .#liquidGlass --no-link --print-out-paths)
glass_client=$(nix build .#liquidGlassClient --no-link --print-out-paths)
nix develop .#cpp --command env QML_IMPORT_PATH="$glass_client/lib/qt-6/qml" \
  node tools/liquid-glass/tests/nested.mjs "$glass_plugin/lib/libliquid-glass.so"
```

Ce test lance un Hyprland dans une fenêtre et un répertoire runtime privés.
L'option `GLASS_TEST_FLOAT=1` stabilise uniquement cette fenêtre de test sur le
compositeur parent, pour éviter que le tiling ne la redimensionne entre les captures.
Il n'y charge le plugin qu'après avoir identifié les sockets de cette session.
Il vérifie le fond animé, une véritable capsule de la barre, l'ajout/retrait
d'un second écran, l'échelle fractionnaire, le déchargement/rechargement et le
retour opaque. Avec `GLASS_TEST_GRIM`, il contrôle également la visibilité du
curseur logiciel, la déformation du fond sur les bords et au cœur de deux
panneaux, la teinte fumée et la conservation des pixels opaques du texte.
Il vérifie aussi le cache, le recadrage, l'absence de traces après déplacement
et redimensionnement, la désactivation/réactivation sans déchargement et une
animation éloignée ne devant pas renouveler les textures du verre.
Les shaders sont aussi validés par CTest. `tests/curvature-test.mjs` évalue les
expressions scalaires du GLSL précédent archivé pour vérifier la monotonie, la cohérence entre
hauteur et pente, la continuité de courbure et de déformation à la jonction,
ainsi que la conservation de la déformation au centre. Il fait partie du build Nix.
Les tests `cushion-source-parity` et `cushion-fixtures` contrôlent les empreintes
du modèle/port audités et les sondes CPU du coussin, sans navigateur ni GPU.
Après toute modification de la forme, revalider les 2346 sondes sur GPU avant
de renouveler `cushion-source.json` (pas de simple mise à jour aveugle du hash).
Les deux tests `pebble-*` et leurs 286 sondes restent disponibles pour l'archive.
Le test imbriqué vérifie aussi que les champs restent en cache au repos et
pendant le rebond uniforme de sélection.

### Comparaison du temps GPU du matériau

Depuis la racine, dans `nix develop .#cpp` :

```bash
cmake -S tools/liquid-glass -B tools/liquid-glass/build -G Ninja -DLIQUID_GLASS_GPU_BENCH=ON
cmake --build tools/liquid-glass/build --target glass-gpu-bench
tools/liquid-glass/build/glass-gpu-bench --probe-cushion tools/liquid-glass/shaders tools/liquid-glass/tests/cushion-fixtures.txt NVIDIA
tools/liquid-glass/build/glass-gpu-bench tools/liquid-glass/shaders tools/liquid-glass/shaders NVIDIA analytic.frag pebble.frag cached
```

`tests/gpu-bench.cpp` crée son propre contexte EGL hors écran ; il ne charge
aucun plugin et ne lit pas le bureau. Il sélectionne explicitement le GPU,
utilise les requêtes temporelles GPU (pas le temps CPU), alterne l'ordre A/B
sur 24 paires après échauffement, et refuse les mesures invalides/disjointes.
Les trois scènes synthétiques (barre, panneau, forte couverture) sont rendues
en 5120×900 aux échelles 1 et 1,6. Le programme échoue si la médiane des ratios
appariés régresse dans un cas. Le benchmark n'est ni installé, ni exécuté
par le plugin ou par le build Nix normal.

Le mode `--probe-cushion` compare hauteurs et déformation au modèle CPU validé,
avec des dérivées numériques indépendantes des dérivées analytiques du shader.
Sur dix formes aux échelles 1 et 1,6 (rayons de 1, 2, 18 et 40 px), l'erreur
maximale mesurée est de 0,526 pixel logique, moyenne 0,0037 ; l'erreur maximale
de hauteur normalisée vaut 0,00044. Les seuils de refus restent 0,75 px et 0,008.
La génération du champ est mesurée séparément, hors du dessin final.
`--probe-pebble` reste utilisable avec `tests/pebble-fixtures.txt` pour l'archive
(erreur maximale 0,168 px, moyenne 0,012).
Omettre `cached` mesure aussi le flou recalculé à chaque dessin. Le test A/B
retourne une régression dès qu'un ratio médian dépasse 1, même de moins de 1 % :
consulter les durées absolues et les chiffres ci-dessus, pas seulement ce code.

Comparaison 0.2.0 / 0.1.5 sur NVIDIA RTX 4000 Ada Laptop : environ 86 %, 67 %
et 27–30 % de temps GPU en moins pour le dessin du matériau selon la scène,
sans hausse mesurée dans les six cas. Le gain inclut le dessin limité aux
capsules au lieu du quad plein écran ; il n'inclut pas la suppression des passes
du champ de distance. Cela ne mesure ni le coût CPU des métadonnées ni le coût
total du compositeur, et ne garantit pas le même résultat sur tous les
GPU/pilotes. Refaire cette comparaison si le matériau change.

Une capture du seul bureau de test peut être produite en définissant
`GLASS_TEST_GRIM` avec le chemin de `grim` ; elle est enregistrée dans
`/tmp/liquid-glass-desktop-test.png`. Le test ferme ses processus à la fin.
