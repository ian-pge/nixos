# Quickshell Messages — backend Go

Le client utilise uniquement l’API publique de Beeper Desktop et son SDK Go officiel,
verrouillé dans `go.mod`. Beeper doit rester lancé avec son API locale activée.
Le WebSocket public reste expérimental ; une évolution incompatible de Beeper peut
nécessiter une mise à jour du client.

## Développement

Depuis la racine NixOS : `nix develop .#go`, puis `cd tools/quickshell/beeper`.
`go test ./...` vérifie le protocole, le transport HTTP/WebSocket, la persistance,
les notifications et les envois incertains. Le test D-Bus crée un bus privé et
est ignoré si `dbus-daemon` n’est pas disponible. `go run . --demo` fournit quatre
conversations fictives sans réseau, trousseau, notifications réelles ni écritures
persistantes ; toutes les actions de messagerie y restent en mémoire.

En usage réel, le panneau demande le jeton créé dans les paramètres de l’API Beeper.
Le backend le vérifie puis le conserve via `secret-tool` dans le trousseau système,
attributs `application=quickshell-beeper` et `service=beeper-api`. Le jeton n’est pas
stocké dans Nix, les brouillons ou les journaux. `BEEPER_ACCESS_TOKEN` peut le remplacer
pour le développement. `BEEPER_API_URL` accepte uniquement une adresse HTTP(S) locale
(par défaut `http://localhost:23373/`).

Au démarrage, le client attend le trousseau et distingue un jeton absent d'un
trousseau verrouillé ou temporairement indisponible via Secret Service. Il retente
la lecture automatiquement sans effacer ni réenregistrer le jeton. Si Beeper est
hors ligne, le jeton reste en mémoire et la reconnexion le réutilise. Le bouton
« Réessayer » relit réellement le trousseau ou relance la connexion existante.
Le champ de jeton n'apparaît que si aucun jeton n'est enregistré ou si Beeper
refuse explicitement cet accès ; une panne réseau ne demande pas un nouveau jeton.

Désactiver **les sons et notifications de bureau de Beeper** dans ses paramètres.
Ne pas mettre les conversations en sourdine pour obtenir cet effet : la sourdine
reste respectée par ce client. L’identité de nos notifications est `Messages`,
avec `desktop-entry=quickshell-beeper`. Le serveur Quickshell gère le rendu et DND.

## Protocole QML

Une ligne JSON par requête : `{"id":1,"method":"chats","params":{}}`.
Réponse : `{"id":1,"result":...}` ou `{"id":1,"error":{"code":"...","message":"..."}}`.
Événement sans identifiant : `{"event":"messagesChanged","data":{"chatID":"..."}}`.
Les identifiants doivent être uniques tant que la requête n’est pas terminée ; les
réponses réseau peuvent arriver dans un ordre différent. Huit requêtes réseau au
maximum s’exécutent en parallèle ; les commandes de focus et brouillon sont ordonnées.

| Méthode | Paramètres / résultat |
| --- | --- |
| `status`, `connect`, `reconnect`, `refresh` | `connect {token}` ; états `loading-token`, `keyring-unavailable`, `needs-token`, `invalid-token`, `connecting`, `connected`, `offline`, `demo` |
| `accounts`, `chats` | Objets API bruts ; `chats {cursor?,direction?}` retourne `{items,hasMore,oldestCursor,newestCursor}` |
| `messages`, `message`, `search` | `{chatID,cursor?,direction?}`, `{chatID,messageID}`, `{query,chatID?,cursor?}` |
| `contacts`, `startChat` | `{accountID,query}`, `{accountID,userID}` ; retour API Chat avec `id` |
| `send` | `{chatID,text,replyToMessageID?,attachment?:{path,type}}` ; retourne `{chatID,pendingMessageID}` |
| `edit`, `delete`, `react` | `{chatID,messageID,text?}`, réaction `{reactionKey,remove?}` |
| `read`, `updateChat` | `{chatID}`, `{chatID,changes:{isMuted?,isPinned?,isArchived?,isLowPriority?}}` |
| `getDraft`, `saveDraft` | `{chatID,text?,attachment?,replyToMessageID?}` ; retour `{text,attachment?,replyToMessageID?}` |
| `setView` | `{chatID,focused,atLatest}` ; seuls les messages visibles dans la conversation au premier plan sont silencieux |
| `stageAttachment`, `clipboardAttachment` | `{path,type?}` ou `{}` ; copie durable et privée `{path,srcURL,type,fileName,mimeType}` |
| `prepareRecording`, `discardAttachment` | `{}` retourne un fichier `.ogg` de type `voice-note` ; `{path}` supprime uniquement une copie de notre répertoire, non référencée par un brouillon |
| `upload`, `download` | `{path}` retourne l’upload API ; `{url}` retourne `{srcURL,error?}` pour les URL média Beeper |

Les événements sont `status`, `chatsChanged`, `chatsDeleted`, `messagesChanged`, `messagesDeleted`, `openChat`, `warning`,
`sendFailed` et `pendingResolved`. `openChat` contient `chatID` et `messageID` quand
la notification vise un message ; un résumé de reconnexion peut ouvrir le panneau
sans conversation spécifique. Les réponses de l’API gardent leurs champs camelCase
et leurs champs facultatifs. Les messages et aperçus HTTP ajoutent `plainText`, une
version sans balises pour les libellés natifs, en conservant `text` intact.
`messagesDeleted {chatID,ids}` permet de retirer les messages déjà chargés, même
hors de la page courante. L’interface doit conserver les curseurs opaques et
traiter les erreurs de capacités provenant du réseau.
Les réponses et événements `status` portent une `revision` croissante par
processus. QML ignore une réponse ancienne arrivée après un état plus récent,
et remet ce compteur à zéro lorsque le processus Go redémarre.

## Fiabilité et médias

Les brouillons et copies de pièces jointes sont dans
`$XDG_STATE_HOME/quickshell-beeper` (sinon `~/.local/state/quickshell-beeper`). Les
répertoires sont privés et `state.json` est écrit atomiquement avec le mode `0600`.
Les copies de fichiers originaux ne sont jamais supprimées par `discardAttachment`.
Les images collées sont limitées à 100 Mio, les fichiers au plafond API de 500 Mio.
Un envoi utilise une pièce jointe : `image`, `gif`, `video`, `audio`, `voice-note`,
`file` ou `sticker`, selon ce qu’accepte le réseau. L’enregistrement/lecture est QML.

Un succès d’envoi signifie **accepté par Beeper**, puis l’identifiant provisoire est
résolu via l’API publique. Le statut final arrive dans `pendingResolved` ou
`sendFailed`. Aucun envoi n’est automatiquement répété, y compris après un échec réseau
ou HTTP 500. `send_uncertain` demande de vérifier la conversation avant tout nouvel
envoi. Les identifiants encore provisoires sont conservés au redémarrage.

Les notifications sont dédupliquées sur disque pendant 30 jours. Le premier chargement
est silencieux ; les messages sortants, anciens, supprimés, lus, masqués, éditions et
réactions ne génèrent pas d’alerte. La sourdine et la suspension de conversation sont
vérifiées via l’API. Une reconnexion resynchronise les conversations et produit au
plus un résumé silencieux pour les messages manqués ; DND ne rejoue pas les alertes.
Le clic revient au panneau QML, jamais à l’interface Beeper. Aucune base privée de
Beeper, extension Chromium ou serveur Matrix interne n’est utilisée.
