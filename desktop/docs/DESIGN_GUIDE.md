# Guide de maintenance du shell Quickshell

Ce guide conserve les raisons des choix et les contraintes difficiles à déduire
d'un seul composant. Le [README](../README.md) centralise installation, commandes
de test et diagnostic. Les valeurs exactes, raccourcis et protocoles détaillés
restent dans le code, l'aide intégrée et les README des outils concernés.

## Architecture et durée de vie

`shell.qml` crée les contrôleurs une fois par session. Son registre `services`
contient uniquement leurs références : pas d'alias de champs, de fonctions
relais ou d'état métier. Les vues parlent à leur contrôleur et demandent les
changements de présentation par signaux.

`ShellCoordinator` décide du mode central, du moniteur cible, des priorités et
de la restauration après authentification. Il ne possède ni modèle de
périphérique, ni mot de passe, ni parseur de protocole, ni processus métier.
`ShellIntegration` expose l'IPC et restaure l'indication de bordure Hyprland.
Les sources QML restent dans `desktop/`, les helpers dans `tools/` et
l'installation dans Home Manager ; séparer les dossiers ne multiplie pas les
services ou les processus par écran.

Chaque écran possède ses vues, mais partage les données et opérations. Un clic
cible son écran ; un raccourci sans cible utilise le moniteur focalisé. Déplacer
un panneau vers un autre écran ne doit ni dupliquer une opération ni effacer un
brouillon. Les écrans non concernés gardent leurs workspaces et n'animent pas
une copie cachée du panneau.

La durée de vie d'une opération n'est pas celle de sa vue. Fermer le Wi-Fi
nettoie scanner, connexion interactive, secret et speed test. Fermer Bluetooth
arrête la découverte, mais une opération native déjà lancée garde son état.
Masquer les updates ne termine pas leur processus. Polkit est un service
générique : une demande externe interrompt puis restaure le panneau et son
moniteur, si celui-ci existe encore.

## Surfaces, géométrie et transitions

### Une surface Wayland stable

Le `PanelWindow` garde la hauteur du moniteur et une zone exclusive fixe.
Animer sa hauteur provoquait des déplacements des modules latéraux lors des
recalculs layer-shell. Seuls les éléments internes changent de taille.
Le masque d'entrée suit les capsules et le panneau réellement présenté ;
l'espace transparent entre eux reste traversable aux clics. Le rebond visuel
ne déplace jamais les zones de clic.

Le plafond des widgets centraux vient de
`WorkspaceSwitcher.expandedImplicitWidth`, calculé avec un slot spécial même
s'il n'est pas ouvert. Une constante recopiée dans chaque widget divergerait
avec la géométrie des workspaces. Mesurer le contenu à sa largeur cible, pas à
sa largeur animée : sinon les retours à la ligne font gonfler puis rétrécir les
notifications et panneaux pendant leur ouverture.

En plein écran, toute la barre du moniteur concerné monte en couche Overlay.
Elle redescend après la fin de la fermeture, sans changer sa géométrie ni sa
réserve. Il n'existe pas d'OSD indépendant à instancier pour ce cas.

### Animation commune

La transformation centrale est monotone, avec décélération à l'arrivée :
pas de ressort, de dépassement de la cible ou de trajet aller-retour.
Une interruption reprend les valeurs effectivement affichées. Source et
destination restent brièvement rendues ensemble, pilotées par une seule
progression ; les composants ne relancent pas chacun leur propre entrée.
Lors d'une séquence rapide de modes, capturer les opacités et translations
courantes au lieu de faire disparaître brutalement les couches intermédiaires.
Un passage entre deux panneaux ne doit pas afficher les workspaces entre eux.

Le rebond de sélection est une exception limitée aux capsules latérales
survolées ou temporairement actives. Une opération de fond ne force pas ce
rebond. Les listes et workspaces ne rebondissent pas ; masquer ou désactiver
une vue termine ses animations.

### Passage entre capsule et messagerie

`BeeperBubble` part du rectangle de la capsule. L'ouverture fige ce rectangle
avant de changer de mode ; la fermeture rejoint la destination actuelle.
Pour passer du chat à un panneau, établir d'abord le panneau cible, puis
fermer le chat. Une seule surface peint le verre jusqu'au relais au même
rectangle final. Deux fonds ou une seconde animation de hauteur produiraient
un dernier mouvement parasite.

Pendant la fermeture, désactiver le contenu, pas son conteneur visuel :
le collecteur de `GlassShape` ignore les éléments désactivés, même par un
parent, ce qui ferait disparaître le verre avant la fin du trajet.
Les workspaces restent masqués jusqu'au retour réel à la capsule, y compris
lorsqu'un OSD apparaît puis expire pendant que le chat est ouvert.

Le chat est centré dans la zone de travail. Les marges externes de
`BeeperBubble` correspondent aux `general.gaps_out` de Hyprland ; les maintenir
cohérentes. Son contenu garde sa mise en page finale pendant la transformation.

## Couleurs et verre

[Theme.js](../ui/Theme.js) est la source des couleurs. Les widgets latéraux et
leurs panneaux centraux partagent leur accent ; ne pas recopier leurs codes
hexadécimaux dans les vues ou dans une seconde table documentaire.
Les couleurs de plateforme Beeper et les repères du clavier sont indépendants
de ces accents, afin qu'un changement de couleur de la barre ne les recolore pas.

Le rose d'action et le jaune d'état ont des rôles distincts dans les workspaces
et contrôles génériques. Les panneaux ayant leur propre accent l'utilisent
pour leurs sélections. Un compteur élevé ne constitue pas à lui seul une erreur ;
distinguer une valeur indisponible de zéro. Les images et icônes fournies par
les applications gardent leurs couleurs. Le thème des bordures Hyprland est
indépendant de celui de Quickshell.

`GlassState.enabled` dépend de la disponibilité du plugin. Le repli opaque
doit rester lisible : ne pas rendre `Theme.background` transparent globalement,
car il sert aussi au texte inversé. `GlassShape` appartient au rectangle qui
porte les transformations et suit son rayon. Après une modification du module
C++, redémarrer le runtime déployé ; un rechargement QML ne recharge pas ce module.

Les sélections internes réutilisent `SelectionSurface` et le verre existant.
Elles ne sont pas une deuxième vitre : pas de `GlassShape`, de flou ou de shader
par ligne. Les sélections pleines inversent le texte pour le contraste ; les
teintes translucides gardent leurs libellés clairs. Le liseré tournant et les
reflets synthétiques de bord ont été retirés volontairement.

## Messagerie

### État, envoi et API

Un `BeeperData` et un backend Go servent toute la session. Les vues par écran
n'activent que le panneau ciblé. La connexion reste vivante quand le chat est
masqué, notamment pour recevoir les notifications. L'interface est en anglais ;
les contenus et noms des conversations ne sont pas traduits.

Ouvrir une conversation, défiler ou écrire ne la marque pas lue. Seuls une
action explicite ou un envoi accepté le font. Un envoi marque jusqu'au dernier
message connu au départ, pour laisser non lus ceux arrivés entre-temps.
Un échec ou un résultat incertain ne change pas la lecture.

Au départ d'un envoi, texte, pièces jointes et réponse sont transférés dans un
instantané persistant distinct du prochain brouillon. Un succès tardif ne doit
jamais effacer ce nouveau brouillon, même s'il est identique. En cas d'échec,
restaurer l'ancien seulement si la saisie est vide ; sinon proposer sa
récupération séparément, sans écraser ni renvoyer automatiquement.
Les pièces jointes des envois incertains restent protégées après redémarrage.
Vérifier la conversation avant de retenter un envoi non confirmé.
Un lot utilise les envois unitaires de l'API dans l'ordre de sélection ; seul le
premier porte le texte et la réponse. Persister la progression avant le fichier
suivant et ne conserver en récupération que les fichiers non encore acceptés.
Une erreur arrête le lot. Les anciens brouillons `attachment` restent lisibles
avec les nouveaux brouillons `attachments`.

Brouillons, sélection et réponses asynchrones sont associés au `chatID`.
Une réponse tardive ne déplace ni le défilement ni la sélection d'un autre chat.
Après succès, seule la conversation concernée retourne en bas ; un geste
manuel libère cette ancre.

`isLowPriority` vient de Beeper. Attendre le succès d'une modification, rejeter
les lectures antérieures puis accepter les modifications d'autres clients.
Ne pas réintroduire de classement local persistant ou de migration distante
des anciens choix d'archives. Les non-lus comptent les conversations, y compris
les marquages manuels, dans tout le catalogue et non dans les seules pages
chargées. Une erreur ou un catalogue incomplet donne un état indisponible,
jamais un zéro ou un total partiel présenté comme exact.

Les réactions sont ordonnées par message et préservent celles des autres
participants. Comparer sans VS15/VS16, puis envoyer la variante exacte admise
par la plateforme ; conserver tons de peau et jointures ZWJ. Identifier notre
participant par les données API, pas par son nom affiché.
Les reçus de lecture doivent être confirmés : la livraison seule ne suffit
pas. Dans Telegram privé, le dernier marqueur confirmé couvre les anciens
messages envoyés ; ne pas étendre cette inférence aux groupes, aux messages
plus récents ou aux envois en attente.

Pour les auteurs, membres et réactions, ne pas inventer une personne à partir
de la photo du groupe. Un total de participants ne se déduit d'une liste
partielle que lorsque l'API garantit sa complétude. Les identités et couleurs
des auteurs restent stables pendant navigation, pagination et transfert d'écran.
Les détails de protocole et de persistance appartiennent au
[backend](../../tools/quickshell/beeper/README.md).

### Pagination, modèles et défilement

`KeyedListModel` réconcilie les snapshots par identité. Remplacer tout le modèle
détruit les delegates, relance les décodeurs et casse les ancres de lecture.
Cela concerne aussi les pièces jointes et les réactions.

La sélection de conversation est un identifiant, pas le `currentIndex` natif
d'une ListView : une activité de fond peut réordonner le catalogue sans ramener
le viewport sur une sélection hors champ. Une navigation explicite révèle la
ligne après avoir arrêté le mouvement précédent ; un geste utilisateur
interrompt le suivi d'une ligne qui grandit. Aucun `forceLayout()` ou parcours
du catalogue à chaque image.

La sélection et son brouillon changent immédiatement, mais le chargement de
l'historique attend une courte pause de navigation. Cela évite de construire
les conversations traversées pendant une répétition de touche. Une cible
explicite, telle qu'une notification, contourne ce délai. Chaque requête porte
sa génération pour rejeter les réponses périmées.

Les curseurs API restent opaques : ne pas en fabriquer depuis un identifiant
ou `sortKey`. Une seule pagination à la fois ; un curseur inchangé termine les
pages et une erreur suspend les tentatives jusqu'à une reprise explicite.
Précharger pendant le défilement avec un throttle, sans attendre sa fin.
La recherche dispose de sa propre génération et pagination ; changer de chat,
de requête, fermer ou naviguer manuellement interrompt la localisation d'un
ancien résultat, sans limite arbitraire de pages.

`BeeperHistory` conserve les hauteurs exactes des messages dans un Flickable :
l'estimation des delegates variables d'une ListView faisait varier le curseur
de défilement pendant un simple scroll. L'Instantiator asynchrone répartit les
créations entre images ; révéler les nouvelles bulles et activer leurs médias
après restauration du viewport. Les panneaux invisibles ne reconstruisent pas
d'historique ; un panneau en cours de fermeture conserve son contenu.

Les positions de layout restent présentes, mais seuls les avatars, médias et
citations proches du viewport chargent leurs ressources. Conserver les dimensions
décodées après déchargement : sinon une pièce jointe change de hauteur à chaque
retour à l'écran. Une recherche binaire limite les mises à jour de visibilité
aux lignes concernées. Seuls les nouveaux messages arrivant en bas d'une
conversation déjà ouverte jouent une entrée, jamais les anciennes pages ou
un rafraîchissement.

`AcceleratedScroll` conserve le nom historique, sans multiplicateur de cadence.
La molette accumule une distance avec durée bornée ; le pavé tactile garde ses
deltas natifs. Ne pas ajouter de `Behavior on contentY` en concurrence avec
Flickable, ni restaurer une ancre au milieu d'un geste.
Voir l'[avertissement Qt sur les hauteurs variables](https://doc.qt.io/qt-6/qml-qtquick-controls-scrollbar.html#varying-delegate-sizes).

### Texte, focus et saisie

Le texte des messages reste brut. Recherche et sélection peignent une couche
échappée avec la même police et le même interligne ; le texte original détermine
seul la géométrie. Ne pas basculer un même Text entre formats brut et riche :
l'ordre des bindings pourrait interpréter brièvement du contenu utilisateur
comme du HTML. Préserver les indices UTF-16 en ignorant casse et accents.
Les liens ouvrables sont limités à HTTP(S) et mailto.

La sélection de texte ne vole pas le focus aux raccourcis de navigation.
Les touches de navigation restent du texte dans les champs ; respecter les
compositions, AltGr et touches mortes. `Ctrl+H/L` passe entre les panneaux en
conservant brouillon, réponse et pièce jointe. Le sélecteur Yazi/Ghostty ouvert
par `Ctrl+F` garde la conversation d'origine, même si la sélection change ;
annulation ou fermeture restaure la saisie sans envoyer. La classe de fenêtre
`dev.me.file` conserve les règles flottantes de Yazi. Pendant son ouverture,
le chat se replie avec son animation habituelle avant de lancer Yazi. Attendre
la fin réelle de cette transition, pas un délai fixe. Il libère alors son grab
et son masque d'entrée ; la barre garde
sa couche normale. À la fermeture de Yazi, le même panneau et le brouillon sont
réaffichés. Ne pas forcer la réouverture si l'utilisateur a fermé le chat ou
choisi un autre panneau entre-temps.

L'ordre des annulations compte : mode Vim, sélection de texte, lecture audio,
modale et aperçus de réponse/pièce jointe ont leurs traitements contextuels
avant la fermeture du chat. L'aide `?` et les handlers sont la référence des
touches exactes ; ne pas maintenir une deuxième liste ici.

En mode normal Vim, le champ doit réellement être en lecture seule, y compris
pour les entrées IME, collages et dépôts. Les commandes utilisent le caractère
produit, pas seulement le code de touche ; une touche morte seule ne doit pas
perdre la commande en attente. Une commande ou session d'insertion forme une
seule étape d'annulation, car l'undo natif Qt peut scinder un remplacement.
La prise de focus interne démarre la saisie ; un simple retour dans la fenêtre
ne doit pas réinitialiser arbitrairement son mode.

La saisie d'emojis restaure le curseur et la sélection, sans envoyer. Le catalogue
et sa licence sont inclus dans `BeeperEmojiData.js` ; `generate-emojis.mjs`
produit son patch de régénération. Un vocal reste un brouillon après arrêt.
Annuler sa préparation à la fermeture ou au changement de chat : un retour
tardif ne doit pas ouvrir le micro. Une connexion perdue n'empêche jamais
d'arrêter un enregistrement déjà lancé.

### Médias et rendu

L'audio possède un lecteur partagé indépendant des delegates, du moniteur et
du chat sélectionné. Scroll, rafraîchissement, changement de conversation ou
fermeture du panneau ne l'interrompent pas. Les contrôles recréés se rattachent
à la même position ; une pause explicite permet de passer à un autre vocal.
Les formes d'onde réelles viennent du backend ; seule la démo peut en inventer.
La molette au-dessus du lecteur continue de faire défiler les messages.

Le plein écran multimédia utilise une surface séparée sans redimensionner la
barre. Une vidéo démarre à l'ouverture, met les lecteurs inline en pause et
s'arrête à la fermeture, même si son téléchargement finit plus tard.
Une vidéo en pause reste en pause après un seek. Les durées API sont en
secondes, celles de Qt Multimedia en millisecondes.

Sur cette machine NVIDIA/Wayland, le chemin VAAPI d'export des textures peut
bloquer le shell. Le runtime choisit donc le décodage logiciel FFmpeg
(`QT_FFMPEG_DECODING_HW_DEVICE_TYPES=,`), tout en gardant le rendu Qt Quick et
Liquid Glass sur GPU. Vérifier des pixels réellement décodés et l'arrêt des
lecteurs avec le harnais `--video` ; `PlayingState` seul ne prouve rien.

Les photos attendent d'être prêtes avant le trajet depuis leur vignette.
Animer transform/opacité, sans redimensionner l'image décodée. Si la vignette
est masquée, rognée ou réaffectée, utiliser un fondu plutôt qu'un trajet vers
une autre image. La règle Hyprland `no_anim` de la surface photo évite un second
fondu de couche ; le fond est seulement assombri, pas flouté.

Garder chat et photo dans le même périmètre de focus. À la fermeture, retirer
l'ancien grab avant de masquer la fenêtre puis créer celui du chat au tour
suivant : réactiver le grab existant laisse un événement `cleared` tardif
annuler le clavier. Tester avec le pointeur hors du chat et une autre fenêtre
ouverte. Un clic extérieur libère le focus sans fermer le chat ; ne pas lier
le grab à la seule visibilité ni reprendre le clavier à l'autre application.

Les bulles utilisent un chemin rempli unique pour éviter un joint transparent
entre pointe et corps. Les médias ne peignent pas une seconde carte dessous.
Conserver texte, avatars et résolution de décodage stables pendant les
animations de sélection ; les transforms évitent les recalculs coûteux de
texte à chaque image. `ClippingRectangle` réalise le masque circulaire :
un rectangle arrondi ordinaire ne découpe pas ses enfants.

## Notifications et coexistence des panneaux

Quickshell possède un seul serveur de notifications et une seule carte,
présentée sur l'écran ciblé à réception. Une nouvelle carte remplace l'ancienne ;
pas d'historique, de file ni de rejeu. Garder l'objet retenu pendant le fade de
fermeture pour que son image reste disponible.

Les notifications recouvrent temporairement les autres modes, dont les états
et opérations continuent. Le guard protège leurs champs sans désactiver puis
réactiver les vues, ce qui perdrait leurs sélections. Une notification seule
ne réclame pas de clavier exclusif. À sa fin, restaurer le mode encore actif,
pas un OSD déjà expiré.

Volume, luminosité et notifications ordinaires coexistent avec le chat dans
la barre. Les autres panneaux centraux le remplacent ; ouvrir le chat les
ferme. Les arrivées MPRIS passives n'ouvrent pas un panneau : les applications
publient aussi leurs vocaux et vidéos comme lecteurs.

Quand le chat est ouvert, supprimer les bannières de messagerie sur tous les
écrans, même sans focus, tout en conservant les sons autorisés. Ouvrir le chat
retire une carte de messagerie déjà affichée sans interrompre son son. Ne pas
mettre ces arrivées en attente pour la fermeture. Supprimer les doublons natifs
Beeper tant que notre client est connecté.
Les conversations Low Priority ne notifient que pour mentions structurées ou
réponses admissibles, avec respect du mute/snooze.

Ne pas déranger expire toutes les arrivées, même critiques, et arrête seulement
les lecteurs de notification appartenant au shell. Musique, appels et micro
ne changent pas. Son état survit au rechargement QML, pas au redémarrage du
processus. Le feedback de la cloche est temporaire : un mode muet persistant
ne maintient ni survol ni rebond.

Chaque arrivée autorisée possède son lecteur de son, sans délai minimal ni file.
Respecter `suppress-sound` ; une mise à jour du même ID ne rejoue pas le son.
Suivre et libérer les lecteurs, y compris après un échec, permet de couper
ceux déjà actifs lors du passage en Ne pas déranger.

Le raccourci Échap du compositeur n'est consommé que si une carte est présente.
Son bail expire après un crash du shell. Dans le sous-mode Voxtype, fermer une
notification ne doit pas annuler la dictée ni quitter ce sous-mode.
Le clic droit de la cloche bascule uniquement le clavier intégré ; son état
vit dans Hyprland, indépendamment de la cloche et de l'état Ne pas déranger.

## Intégrations système

### Workspaces

La sélection est locale à chaque moniteur, l'occupation est globale.
Quickshell 0.3.1 peut traiter `workspacev2` sur l'ancien écran si l'événement
précède `focusedmon` : utiliser l'instantané `lastIpcObject.activeWorkspace.id`
rafraîchi par `WorkspaceMonitorSync`, pas le focus global ni directement
`monitor.activeWorkspace`. Regrouper les événements avec l'API native,
sans polling `hyprctl`. Un écran absent ne reprend pas le workspace d'un autre.

La référence de moniteur vient de Bar ; la rechercher dans chaque sélecteur
avait créé une boucle de binding. Largeur et rendu suivent le même identifiant
local, y compris pour les special workspaces. Les tests IPC utilisent des
sockets privés, sans déplacer les workspaces réels.

L'indication de bordure de la fenêtre Hyprland doit être restaurée au démarrage,
à la fermeture du dernier overlay et à la destruction de `ShellIntegration`,
afin qu'un redémarrage ne laisse pas la bordure inactive.

### Réseau, audio et luminosité

Wi-Fi et Bluetooth utilisent les modèles natifs Quickshell. Garder le scanner
Wi-Fi actif tant que le sélecteur est ouvert : le couper masque les réseaux
inconnus. La fin du spinner ne termine pas le scanner. Une roue de navigation
ne s'anime qu'après une action utilisateur, pas à chaque résultat de scan.

Le speed test est explicite ; fermeture et timeout arrêtent son groupe de
processus. Les générations rejettent toute sortie tardive. Transmettre un
secret Wi-Fi directement à l'API native, jamais dans des arguments shell.

Les coches audio suivent les périphériques effectifs, même lorsqu'une
préférence vient d'être écrite. PipeWire possède volume et mute ; WirePlumber
libère la préférence de la direction concernée lors d'un hotplug ou changement
de route. Désactiver la restauration des anciens défauts ne suffit pas à
libérer une préférence actuelle. Volume, mute et nouveaux flux ne constituent
pas un hotplug.

MPRIS préfère `playerctld`, qui suit le dernier lecteur actif. La pause/reprise
pendant la dictée appartient à Voxtype ; le contrôleur QML ne doit pas ajouter
une deuxième politique concurrente.

Chaque écran affiche sa propre luminosité. Une valeur externe inconnue ne
reprend jamais celle de la dalle interne. Les lectures initiales/topologiques
ne font ni écriture ni OSD. Les commandes DDC sont regroupées en préservant les
inversions et la saturation à chaque pas ; invalider les réponses et le bus
mémorisé quand les moniteurs changent. Les mesures internes ne remplacent pas
une consigne en attente. Voir le [helper luminosité](../../tools/quickshell/brightness/README.md).

### Batterie et télémétrie

Le branchement prime sur l'alerte de niveau : icône et pourcentage sont verts
branchés, rouges débranchés sous 20 %, sinon dans l'accent normal. Chaque
appareil est indépendant, sans éclair ajouté. Un pourcentage inconnu n'est
pas une batterie vide.

`!UPower.onBattery` couvre une batterie pleine ou à charge limitée ; une
décharge explicite doit néanmoins retirer le vert si l'état global est en
retard. Le clavier Agar ne fournit pas son branchement par Bluetooth : son
identité USB précise et une télémétrie fraîche servent d'indice. Cela fonctionne
via un hub, mais pas sur un chargeur mural sans liaison USB au PC. Un niveau de
100 % ne prouve jamais un branchement.

Les collecteurs système/GPU sont partagés ; les tops de processus sont abonnés
seulement quand le panneau est réellement visible. Les générations évitent
de présenter un ancien top après réouverture. Un collecteur expiré, une carte
en veille et une vraie mesure à zéro sont trois états distincts.
Ne pas initialiser NVML avant d'avoir vérifié la veille PCI, car cela réveillerait
la NVIDIA. Les limites et unités appartiennent aux README
[système](../../tools/quickshell/system-stats/README.md) et
[GPU](../../tools/quickshell/gpu-monitor/README.md).

### Lanceurs

Le catalogue applications utilise `DesktopEntries`, sans scruter périodiquement
les fichiers desktop. Une activation d'instance existante doit aussi fonctionner
depuis un autre workspace normal ou spécial. Une recherche ne réserve pas
les lettres ordinaires aux commandes de navigation.

TabCtl fournit les onglets et le helper normalise ses erreurs en JSON.
Les favicons viennent de la base SQLite locale, sans téléchargement.
Activer un onglet ne suffit pas : focaliser aussi sa fenêtre Hyprland.
L'extension Chrome est installée manuellement ; Home Manager possède le
manifeste Native Messaging. Ne pas lancer `tabctl install` sur ce manifeste.
Diagnostic et protocole : [helper Chrome](../../tools/quickshell/chrome-tabs/README.md).

## Stockage

Cmd+Y et le clic sur la capsule stockage ouvrent le même mode `storage` sur
l'écran concerné. Il reprend la largeur maximale, le morphing et la politique
clavier de la capsule centrale ; ne pas ajouter une fenêtre ni une animation
d'entrée autonome. Accent principal `Theme.sideDisk`, couleurs de parts issues
de la palette existante, six libellés et tailles lisibles sans dépendre des couleurs.

L'espace occupé/libre réel reste séparé du camembert des tailles mesurées.
Sur Btrfs, les blocs de fichiers partagés peuvent apparaître plusieurs fois :
le graphique indique « Répartition estimée » et utilise la somme des catégories,
jamais un redimensionnement silencieux pour correspondre au total du disque.
Une valeur absente affiche `—`, un zéro mesuré reste `0 Gio`, et une mesure
partielle indique une borne inférieure. Les six lignes restent présentes, même
quand VM vaut zéro. Applications et caches conservent deux sous-totaux.

Le contrôleur partagé conserve les mesures 30 minutes. R/le bouton actualise,
Q/Échap ferme. Aucun nettoyage n'est disponible. Le service système ne lit que
des métadonnées et publie un rapport atomique ; aucun scan récurrent par écran
ni travail lourd dans le collecteur CPU/RAM. Une erreur conserve la dernière
mesure et sa date. Les fixtures QML désactivent les vrais services.

Le service fixe laisse le shell non privilégié : la règle Polkit n'autorise
que la session locale active de l'utilisateur prévu à demander son démarrage.
Fermer le panneau laisse finir l'analyse. Rapport, cache et contrat de mesures :
[collecteur stockage](../../tools/quickshell/system-stats/README.md#on-demand-storage-breakdown).

## Updates et authentification

Le build et l'installation sont deux décisions distinctes. Un résumé de
processus actualise l'affichage, mais ne confirme jamais l'installation.
Seul `installUpdate()`, déclenché explicitement, transmet `install\n`.
Ne pas injecter Enter dans la session réelle pour vérifier une présentation.

L'installation réutilise le résultat construit et prépare la génération de
démarrage avec `boot`, sans redémarrer les services de la session courante.
L'état de redémarrage requis persiste jusqu'à ce que `/run/current-system`
corresponde à la génération attendue. Le checker et les opérations partagent
un verrou ; build, installation et nettoyage ne se chevauchent pas.
Les empreintes du flake conditionnent la réutilisation d'un lock candidat.
Le [README des helpers](../../tools/quickshell/update/README.md) possède les
détails de cache, rollback et activation privilégiée.

Une fin sans état terminal est un échec, même avec code zéro. Les générations
isolent les sorties des tentatives précédentes. Les logs volumineux du
nettoyage restent dans `quickshell/top-bar/clean.log`, pas dans un flux de
lignes QML ; l'espace récupéré vient d'une mesure avant/après.

Le formulaire Polkit ne stocke jamais une réponse dans les arguments,
l'environnement, les fichiers ou les logs. L'effacer avant soumission et à
chaque changement de défi/demande. Échap masque et nettoie le formulaire sans
confirmer l'opération ni annuler implicitement la demande native.
Les tests utilisent des transports fictifs et aucun agent système réel.

## Calendrier et météo

Le calendrier manipule des dates civiles locales : ne pas les convertir
implicitement en UTC. Sa hauteur découle des semaines et des données, pas
d'une passe de layout à la largeur animée. Un code inconnu, des températures
incomplètes ou un jour hors couverture ne doivent pas inventer de météo.
Les données passées sont des modèles archivés, pas des observations mesurées.

La ville manuelle est temporaire. Une nouvelle ouverture redétecte la
localisation IP ; restauration après notification/Polkit ou déplacement du
panneau conserve la consultation. Séparer les caches automatique et manuel,
vider l'ancienne ville à la sélection et rejeter les réponses périmées.
Minuit suit le nouveau jour seulement tant que l'utilisateur n'a pas choisi
une autre date.

Un seul `WeatherData` sert tous les écrans ; pas de requête par case ou moniteur.
Un cache périmé devient indisponible même sans nouvelle réponse. La localisation
IP est une estimation, notamment avec VPN ou selon IPv4/IPv6, jamais une
position physique certifiée. Fournisseurs, couverture et protocole de cache :
[helper météo](../../tools/quickshell/weather/README.md).

## Limites d'utilisation

Seules les CLI officielles déjà authentifiées accèdent aux comptes. Ne pas
réutiliser leurs fichiers de credentials ni des endpoints privés : les CLI
possèdent le renouvellement et la compatibilité de leur authentification.
Les protocoles restent expérimentaux et chaque champ doit être validé.
Une absence de valeur n'est pas zéro ; conserver une dernière lecture avec
son erreur plutôt que présenter un résultat frais inventé.

Claude reçoit des requêtes de contrôle sans prompt, sans sauvegarder de session,
et sans lancer de hooks ou de serveurs MCP. Ne pas ajouter `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` :
cela ferait relire le cache local plutôt que l'usage courant.
Codex utilise `account/rateLimits/read` via app-server ; seuls ses quotas
principaux sont affichés, pas les réserves expérimentales.
Les crédits de réinitialisation ne sont jamais consommés ; pour Claude,
un statut de grants absent reste inconnu et renvoie à la page d'usage.

Les pourcentages sont arrondis à l'inférieur : 100 % doit signifier réellement
atteint. Les processus vivent le temps d'une lecture à la demande, avec timeout
et arrêt forcé si nécessaire, sans polling permanent panneau fermé.
`desktop.nix` épingle les mêmes versions de CLI que le profil utilisateur.
Les fixtures simulent les deux protocoles sans contacter les fournisseurs.

## Clavier et saisie

L'overlay HHKB est tenu par des événements Hyprland ordonnés et n'acquiert ni
focus clavier ni entrée souris. Les relâchements de touche/modificateur, reloads
et changements de sous-mode doivent le fermer. Tab doit être consommé pendant
l'overlay sans déclencher la dictée ; en dehors, il conserve son rôle normal.
Les labels suivent bindings et XKB, sans supposer les combinaisons Fn du firmware.

Lafayette utilise une touche morte à verrouillage ponctuel, distincte de
Compose sur Caps Lock et d'AltGr. Tester l'appui puis le relâchement réel, pas
seulement un symbole isolé. Le keymap est compilé depuis les sources épinglées
dans `home_manager/hyprland/lafayette.nix`, sans modifier firmware, XKB système
ou table Compose globale.
Pour revenir à l'ancien agencement, retirer `kb_file`, remettre
`kb_layout = "fr"`, `kb_variant = "us"`, conserver `compose:caps` et aligner
le diagramme. Les commandes de validation sont dans le README.

## Validation ciblée

Utiliser les commandes et environnements du [README](../README.md#build-preview-and-test).
Pour une animation, contrôler ouverture, interruption, arrivée et fermeture ;
une capture finale ne valide ni le trajet ni le relais de surface.
Vérifier aussi le deuxième écran, la stabilité de la réserve Hyprland et le
retour du focus/de la bordure.

Les suites Wayland couvrent le vrai rendu et les cycles multimédia, les fixtures
offscreen les états et interactions. Les tests de contrôleurs ne doivent ni
envoyer de messages, ni modifier les réseaux, ni installer/nettoyer le système.
Les détails déjà couverts par le code et ses assertions ne nécessitent pas
une nouvelle copie documentaire ; ajouter ici le motif d'un choix ou le piège
que cette vérification protège.
