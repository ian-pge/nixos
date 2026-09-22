# Liquid Glass — fonds des widgets Quickshell

Plugin local C++ / GLSL pour Hyprland 0.56.2, accompagné d'un module Qt pour
Quickshell. Il traite les fonds des capsules
et du panneau central de la barre Quickshell. Les textes, icônes, actions et
animations restent dessinés par Quickshell. Aucune interaction entre bulles
n'est ajoutée et Hyprlock conserve son rendu précédent.

## Fonctionnement

Le plugin intervient juste avant le dessin de la surface `quickshell-top-bar`.
Il conserve l'image du bureau à cet instant (fenêtres et vidéos comprises),
dessine le contenu de Quickshell dans un framebuffer transparent et utilise
les formes exactes transmises par les composants `GlassShape`. Le shader
calcule chaque rectangle arrondi directement à la résolution de l'écran,
sans carte intermédiaire à agrandir. Il réfracte le fond puis compose les
textes/icônes originaux par-dessus.
Les différentes capsules restent indépendantes ; la zone vide de la grande
surface de la barre reste transparente et ne change pas de géométrie.

Une même surface bombée détermine les normales, la déformation et
l'épaisseur virtuelle. Le corps est parabolique ; un ménisque circulaire
régularisé raccorde le bord au corps avec une pente continue. Les petites
capsules gardent un ménisque plus étroit. La déformation reste bornée à
36 pixels logiques avec l'indice de référence 1,5.

Le reflet synthétique de Fresnel et le contre-bord sombre sont supprimés :
aucun liseré blanc ni assombrissement de contour n'est ajouté, y compris
dans le chemin raster de repli. La courbure continue à déformer le fond réel,
avec le même fumé et sans retour de l'ancien contour tournant.
Le filtre à cinq échantillons garde les mêmes poids et le même rayon partout :
**aucun adoucissement variable selon l'angle** n'a été ajouté.
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
vérifier la marge d'échantillonnage de 40 pixels dans `plugin.cpp`.

Le chemin analytique supprime la génération et le stockage de la carte de
distance. Il ne nécessite plus que sept lectures de texture par pixel de verre
(contre douze en 0.1.5). Les capsules sont regroupées dans un dessin instancié :
le shader ne parcourt pas toute la surface transparente de la barre.
Les pixels de premier plan totalement opaques
sortent immédiatement, sans calculer un fond invisible. Il n'y a ni
suréchantillonnage, ni rayon volumétrique, ni texture de reflet supplémentaire.

Référence du fumé : [transmission de Beer-Lambert](https://pbr-book.org/4ed/Volume_Scattering/Transmittance).

Le rendu reste sur le GPU. Le contenu Quickshell et le masque de repli sont mis en cache
entre les commits et les changements de géométrie, d'échelle ou d'opacité.
Le fond est recadré sur l'ensemble des capsules connues, avec
une marge de 40 pixels logiques pour la réfraction et le filtrage. Seule cette
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
rendu, les mises à jour du contenu et les pixels copiés/composés. `referencePixels`
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
Il n'y charge le plugin qu'après avoir identifié les sockets de cette session.
Il vérifie le fond animé, une véritable capsule de la barre, l'ajout/retrait
d'un second écran, l'échelle fractionnaire, le déchargement/rechargement et le
retour opaque. Avec `GLASS_TEST_GRIM`, il contrôle également la visibilité du
curseur logiciel, la déformation du fond sur les bords et au cœur de deux
panneaux, la teinte fumée et la conservation des pixels opaques du texte.
Il vérifie aussi le cache, le recadrage, l'absence de traces après déplacement
et redimensionnement, la désactivation/réactivation sans déchargement et une
animation éloignée ne devant pas renouveler les textures du verre.
Les shaders sont aussi validés par CTest.

### Comparaison du temps GPU du matériau

Depuis la racine, dans `nix develop .#cpp` :

```bash
cmake -S tools/liquid-glass -B tools/liquid-glass/build -G Ninja -DLIQUID_GLASS_GPU_BENCH=ON
cmake --build tools/liquid-glass/build --target glass-gpu-bench
tools/liquid-glass/build/glass-gpu-bench /chemin/vers/shaders-reference tools/liquid-glass/shaders NVIDIA analytic.frag
```

`tests/gpu-bench.cpp` crée son propre contexte EGL hors écran ; il ne charge
aucun plugin et ne lit pas le bureau. Il sélectionne explicitement le GPU,
utilise les requêtes temporelles GPU (pas le temps CPU), alterne l'ordre A/B
sur 24 paires après échauffement, et refuse les mesures invalides/disjointes.
Les trois scènes synthétiques (barre, panneau, forte couverture) sont rendues
en 5120×900 aux échelles 1 et 1,6. Le programme échoue si la médiane des ratios
appariés régresse dans un cas. Le benchmark n'est ni installé, ni exécuté
par le plugin ou par le build Nix normal.

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
