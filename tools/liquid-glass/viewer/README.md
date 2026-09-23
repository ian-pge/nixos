# Atelier verre — visualiseur Three.js

Un atelier interactif pour comparer le **dôme coussin des widgets** au galet
précédent (0.4.0) et au profil parabolique (0.2.5). Le coussin validé est
sélectionné par défaut et utilisé par le compositeur depuis la 0.5.0,
sous forme d'un champ GPU en cache.
L'application reste indépendante : aucun accès IPC à Hyprland, aucune écriture
dans les shaders. Ses réglages ne modifient pas les widgets de la barre.

## Lancer

Depuis la racine de la configuration NixOS :

```bash
nix develop .#threejs
cd tools/liquid-glass/viewer
npm ci --ignore-scripts
npm run dev
```

Ouvrir <http://127.0.0.1:5173>. Le serveur écoute uniquement en boucle locale
et refuse de choisir silencieusement un autre port si 5173 est déjà occupé.
`Ctrl+C` arrête le serveur lancé dans ce terminal.

Avec direnv, `cd tools/liquid-glass/viewer` puis `direnv allow` active le même
shell automatiquement. `.envrc` ne lance ni installation npm ni serveur.
Le flake Git ignore `node_modules`, `dist` et les résultats de tests.
Pas de paquets npm globaux, pas de rebuild NixOS, pas de seconde copie du flake.

Node.js/npm viennent du flake verrouillé. Three.js, Vite, TypeScript et
Playwright viennent du `package-lock.json` propre à ce projet. Toutes les
ressources graphiques sont procédurales/locales ; aucun CDN ou service distant
n'est contacté par la page après installation des dépendances.

## Utiliser

- Glisser : tourner autour du verre, y compris dessous. Molette : zoomer.
  Clic droit : déplacer. Les flèches déplacent la vue quand le canvas a le focus.
- Perspective, Dessus, Profil et ↺ : angles fixes et recentrage.
- « Coussin · widgets » / « Galet précédent », en haut de la vue, permettent de comparer
  les volumes sans changer de caméra, de matériau ni d'échelle.
- Lanceur : 480×398 px, rayon 18, dimensions nominales de `AppLauncher.qml`
  et `Bar.qml`. La largeur réelle peut être limitée par la barre/son écran.
- Capsule : 260×36 px, rayon 18. Calendrier : exemple de 434×398 px,
  la hauteur réelle dépendant des données affichées.
- Largeur, hauteur et rayon modifient uniquement le maillage de cette page.
- « Tester des coins serrés · 2 px » ne change que le rayon, pour vérifier le
  dessus avec des coins presque carrés. Utiliser Mat pour comparer les volumes.
- Verre : matériau Three.js transmissif **illustratif**. Mat : lire les volumes
  sans reflets transparents. Maillage : inspecter les triangles.
- Coupe centrale : retire la moitié avant ; le profil est tracé en vert.
- Teinte de sélection : modifie les couleurs des sommets, jamais leur position.
- Fond plat illustratif : ferme le volume pour faciliter sa lecture ; ce fond
  n'est pas une seconde interface optique du shader du compositeur.
- Le menu « Profil de surface » propose aussi les profils précédents archivés.

### Coussin validé pour les widgets

`cushion.ts` dissocie le contour exact du bombé. Une application harmonique du
disque vers le rectangle arrondi porte une calotte elliptique : les détails
angulaires serrés du contour s'atténuent vers le sommet, au lieu de reproduire
de petits rayons sur les sections du dessus. Le profil garde exactement les
mêmes largeur, hauteur, rayon extérieur et hauteur maximale que le galet.
L'éclairage, les matériaux, le nombre de triangles et le calcul des normales
du maillage ne changent pas entre ces deux modes : ce sont les positions des
sommets qui produisent le nouveau relief.

La frontière est échantillonnée en 2048 points et décomposée en 96 modes
impairs de Fourier. Chaque mode d'ordre `n` est pondéré par `rho^n` ; la hauteur
vaut `hauteurMax * sqrt(1 - rho²)`. Une correction résiduelle en `rho^193`
restitue le contour exact au bord sans raccord discret dû à la troncature.
Le sommet est régulier et tend vers une calotte elliptique. La coupe centrale
inverse cette même géométrie, elle n'est pas une courbe illustrative séparée.

Le compromis assumé : contrairement à la bande uniforme du galet, le coussin
ne force pas la même hauteur à distance égale des côtés et des coins. Il
répartit le bombé plus largement. Un rayon très faible reste nécessairement
serré au contour ; le coussin vise les marques qui remontent sur le dessus,
pas une promesse d'absence de toute ligne dans les reflets.

Les tests contrôlent le contour, la hauteur, les symétries, l'absence de replis
sur des formes allongées et la cohérence coupe/maillage. Aux rayons 1, 2 et
18 px du lanceur, les pics de courbure des sections à 60 et 80 % de hauteur
sont réduits d'au moins 45 % face au galet : mesure sur la géométrie réelle,
indépendante des normales ou de l'éclairage.
Le cache CPU des coefficients du visualiseur ne contient qu'une forme et
aucune boucle de rendu au repos n'est ajoutée.

Le port natif est dans `../src/cushion-field.hpp` et `../shaders/cushion-field.*`.
Il calcule les mêmes coefficients et échantillonne le carré de la hauteur et
son gradient dans un quart symétrique FP16. `analytic.frag` retrouve la normale
et la hauteur pendant la réfraction. La résolution va de 256 à 1024, jusqu'à
2048 pour les coins exceptionnellement serrés. Sur 2346 sondes CPU/GPU, l'écart
maximal de déformation mesuré sur NVIDIA est de 0,526 pixel logique (moyenne
0,0037). Les rayons de 1 et 2 px sont inclus. Le coût du dessin en cache reste
comparable au galet ; reconstruire un champ est plus cher (environ 1,73 ms CPU
et 0,050 ms GPU). Voir le README parent pour les limites de ces microbenchmarks.

### Galet précédent (archive 0.4.0)

`pebble.ts` construit des contours horizontaux emboîtés, tous à hauteur
constante, qui montent vers un seul sommet. Le contour extérieur reste
**exactement le même rectangle arrondi** (mêmes largeur, hauteur, rayon).
La hauteur maximale est celle du profil précédent, pour comparer la forme et
non deux épaisseurs arbitrairement différentes.

Près du bord, les contours sont des décalages parallèles du contour extérieur :
à distance égale du bord, la hauteur est identique sur les côtés et dans les coins.
Cette zone s'étend sur `min(0.4 * rayon, 0.12 * demi-petit-côté)`.
Plus loin, les contours deviennent progressivement circulaires pour rejoindre
le sommet sans plateau ni ligne de crête centrale. Le raccord est C2 ; aucun
rayon intérieur n'est brusquement coupé à zéro. Les normales du galet dans
Three.js sont calculées sur son maillage ; le compositeur échantillonne un
champ de normales dérivé du même modèle, sans redessiner ce maillage à chaque frame.

Pour supprimer les marques des quatre zones latérales sur le dessus, les
contours intérieurs ne sont plus composés de segments droits raccordés à des
arcs de cercle. Leur géométrie est une somme de deux ellipses et d'un disque,
avec une courbure positive et continue dans toutes les directions. Les axes
sont calculés pour conserver la largeur et la hauteur de chaque contour.
Cet arrondi apparaît progressivement après la bande extérieure inchangée ;
le contour du widget, son rayon et sa hauteur maximale ne changent pas.
Il s'agit d'une modification des positions des sommets, pas d'un réglage de
lumière, d'un filtre sur les normales ou d'une augmentation du nombre de triangles.

Pour le lanceur nominal, à 18 px du bord, l'ancien volume donne environ
452 / 301 / 111 unités sur le côté, en haut et au coin intérieur ; le galet
donne environ 266 / 267 / 257 après le lissage du dessus. Les épaules deviennent donc beaucoup plus régulières.

Le port natif archivé est dans `../src/pebble-field.hpp` et `../shaders/pebble-field.*`.
Il stocke un quart symétrique de la hauteur et des normales dans une texture
FP16 de 256 à 1024 pixels de côté, puis `pebble.frag` la lit pendant la
réfraction. Le bord extérieur reste calculé analytiquement. Un changement du
fond, un déplacement ou un rebond uniforme ne reconstruit pas le champ.
286 sondes CPU/GPU sur six formes et deux échelles ont donné moins de 0,2 pixel
logique d'écart de déformation sur NVIDIA. Ce contrôle porte sur la géométrie,
pas sur une identité entre les matériaux Three.js et Hyprland.

### Hauteur et fidélité

Le port CPU de `profile.ts` archive l'ancien profil : distance au bord, corps
parabolique, ménisque reparamétré et gradient analytique. `pebble.ts` archive
le galet ; `cushion.ts` définit le profil actuel. Les dimensions sont des pixels
logiques. Le champ de hauteur n'est PAS une épaisseur en millimètres : pour le
lanceur nominal, sa hauteur au centre est d'environ **642 unités mathématiques**.
Cela pilote la normale du shader ; il ne simule pas un bloc physique de 642 mm.

La vue initiale applique **×0,08 à l'axe vertical uniquement** pour faciliter
la lecture du volume. Le badge indique toujours ce facteur. « Échelle verticale
×1 » affiche les valeurs brutes du profil sélectionné, avec une caméra adaptée. Les normales du maillage
suivent cette mise à l'échelle. Le petit graphique montre une hauteur relative,
indépendante de l'échelle d'affichage.

La transparence, l'éclairage, l'absorption et la réfraction du matériau Three.js
ne prétendent PAS reproduire le shader écran de Hyprland. C'est un visualiseur
de forme ; le fond sous la vitre est une grille de démonstration, pas le bureau.
La géométrie de dessus est échantillonnée plus densément près du bord. Le fond
plat est explicitement illustratif. Aucun reflet de ce visualiseur n'est ajouté
au verre de la barre.

`check-shader.mjs` vérifie les sources auditées du coussin (`../cushion-source.json`),
du galet (`../pebble-source.json`)
et l'empreinte du profil précédent (`profile-source.json`, source `previous.frag`)
avant développement, compilation et tests. Si le modèle ou son port évolue,
revalider la parité CPU/GPU avant de renouveler ces empreintes ; ne pas contourner
ce contrôle. Le serveur de développement surveille aussi ces sources et affiche
une erreur en cas de divergence. Elles sont lues par Node mais ne sont pas
exposées via HTTP : seul le dossier du visualiseur est servi.

## Vérifier et construire

```bash
npm test
npm run build
npm run test:browser
```

Les tests numériques vérifient centre/bords, symétrie, gradients, raccord de
courbure, normales du maillage, géométries étroites et absence d'épaisseur
ajoutée par la sélection. Ceux du galet vérifient aussi le contour conservé,
l'égalité de hauteur autour du bord, l'emboîtement des contours et la régularité
des épaules, ainsi que la continuité de courbure des contours supérieurs et
la disparition des anciens sauts de courbure dans leurs positions. Le test navigateur vérifie le rendu WebGL, les
contrôles, le défilement mobile et l'arrêt des frames au repos.

Le test utilise Chrome déjà installé à `/run/current-system/sw/bin/google-chrome`,
dans un profil temporaire, avec rendu logiciel explicite pour être reproductible.
Sur une autre machine, définir `GLASS_VIEWER_CHROME=/chemin/vers/chrome`.
Il ne télécharge pas de navigateur et ne modifie pas le profil Chrome normal.
Il lance son propre serveur sur 5174 pour laisser la prévisualisation sur 5173
ouverte pendant les tests. L'accès HTTP hors du projet est testé.
La page normale utilise le GPU choisi par le navigateur et borne le pixel ratio
à 1,5. Il n'y a pas de boucle de rendu continue au repos ni en onglet masqué.

`npm run build` produit `dist/`, servi par `npm run preview` ou n'importe quel
serveur statique. Aucun Node.js n'est nécessaire côté client.

Si lancé pour cette session comme service utilisateur transitoire, son état
et son arrêt sont accessibles avec :

```bash
systemctl --user status liquid-glass-viewer.service
systemctl --user stop liquid-glass-viewer.service
```

Ce service n'est pas activé au démarrage et ne touche pas au service Quickshell.
