# Quickshell Assistant — backend Go

Conversations Qwen et OpenAI de l'encoche du bas de Quickshell, et moteur de
correction orthographique partagé par la messagerie et l'extension Chrome.
Chaque conversation passe par son propre processus `pi --mode rpc` (paquet `pi`
de l'input `llm-agents`, chemin fixé par le wrapper Nix via
`QUICKSHELL_ASSISTANT_PI`). Aucune donnée Beeper n'entre dans ce processus.

| Conversation | Modèle pi | Outils | Données |
| --- | --- | --- | --- |
| `qwen` | `ollama/huihui_ai/qwen3.5-abliterated:9b` | `read,grep,find,ls` : lecture seule | restent sur l'ordinateur |
| `openai` | `openai-codex/gpt-6.1-sol` | `read,bash,edit,write,grep,find,ls` | partent chez OpenAI |

La liste d'outils est fixée au lancement de pi : Qwen ne peut ni écrire ni
lancer de commande, quelle que soit la demande. OpenAI agit avec les droits de
l'utilisateur, sans confirmation par appel (comportement documenté de pi).
Seul OpenAI connaît le dossier des captures d'écran (`QUICKSHELL_ASSISTANT_SCREENSHOTS`,
relatif au dossier personnel, fixé par Nix depuis `home_manager/screenshots.nix`) :
ses consignes lui demandent de les ouvrir avec `read` seulement quand on en parle. Les
deux travaillent depuis la racine `/` et peuvent lire tout ce que l'utilisateur
peut lire. pi est lancé avec `--no-extensions`, `--no-skills`,
`--no-mcp`, `--no-context-files` et `--no-approve` : seuls ces outils et nos
consignes système sont chargés. Il utilise `~/.pi/agent` pour l'authentification
OpenAI (`auth.json`) et le fournisseur Ollama (`models.json`, généré par Home
Manager dans `home_manager/quickshell.nix` : réflexion `off` ou `high` seulement,
envoyée comme `reasoning_effort` `none` ou `high`, et 16 384 tokens de sortie
partagés entre réflexion et réponse).
Ollama sert Qwen avec une fenêtre de 32 768 tokens (`system/ollama.nix`).

La correction Qwen et le déchargement GPU appellent directement Ollama, sans
proxy ni redirection. La correction utilise toujours la réflexion activée
(`think: true`, le maximum exposé par ce Qwen), avec 16 384 tokens partagés
entre réflexion et réponse et un délai maximal de cinq minutes. Échap reste
disponible pour annuler le calcul. Ce choix est indépendant du niveau choisi
pour la conversation Qwen. La correction GPT lance un pi éphémère, sans outils,
session enregistrée, extensions, MCP ni accès aux instructions du répertoire.

## Développement

Depuis la racine NixOS : `nix develop .#go`, puis `cd tools/quickshell/assistant`
et `go test ./...`. Le binaire de test joue lui-même un `pi --mode rpc` scripté
(`FAKE_PI_LOG`) et des serveurs HTTP locaux remplacent Ollama : les tests ne
contactent aucun modèle. Le paquet est `packages/quickshell/assistant.nix`. Quand
les dépendances changent, remettre `vendorHash` à `lib.fakeHash`, construire une
fois, puis reporter le hash indiqué par Nix.

## Persistance

`$XDG_STATE_HOME/quickshell-assistant` (sinon `~/.local/state/quickshell-assistant`),
en `0700`, conservé par l'impermanence :

- `state.json` (`0600`, écrit atomiquement) : par conversation, les messages
  affichés, le brouillon et l'identifiant de session pi ; plus la conversation
  sélectionnée. La version 1 (Qwen seul) devient la conversation `qwen`.
- `sessions/<conversation>/` : sessions pi, qui portent le contexte du modèle
  (outils, compaction). Un redémarrage reprend la même session.

Une réponse en cours lors d'un arrêt devient « interrupted » ; elle n'est jamais
relancée. Réinitialiser efface l'historique affiché et ouvre une nouvelle session
pi, donc un contexte vide ; le brouillon est conservé.

## Protocole QML

Une ligne JSON par requête : `{"id":1,"method":"status","params":{"conversation":"qwen"}}`.
Réponse : `{"id":1,"result":…}` ou `{"id":1,"error":{"code":"…","message":"…"}}`.
`conversation` vaut `qwen` (défaut) ou `openai`. Les commandes sont traitées dans
l'ordre ; seules `unload` et `correctText`, qui attendent Ollama, s'exécutent à
part (quatre au plus).

| Méthode | Paramètres → résultat |
| --- | --- |
| `status` | `{conversation}` → `{conversation, revision, resetRevision, generating, unloading, thinkingLevel, thinkingLevels, items, hasMore, oldestCursor, draft, selected}` (50 derniers messages) |
| `select` | `{conversation}` mémorise la conversation affichée |
| `messages` | `{conversation, cursor?}` → page ; curseurs opaques |
| `send` | `{conversation, text}` (16 Ko au plus) → `{messageID}` ; démarre pi au premier message ; refusé pendant une réponse |
| `cancel` | `{conversation}` envoie `abort` à pi ; le texte reçu est gardé (`stopped`) |
| `reset` | `{conversation}` → snapshot vide, nouvelle session pi, brouillon gardé |
| `unload` | `{}` arrête une réponse Qwen, puis `keep_alive: 0` ; → `{unloaded: true}` si Ollama confirme |
| `setThinking` | `{conversation, level}` → métadonnées ; Qwen `off`/`high`, OpenAI `low` à `xhigh` ; enregistré, passé à pi par `--thinking` au lancement et `set_thinking_level` ensuite |
| `search` | `{conversation, query}` → `{ids}` ; chaque mot, sans casse ni accents |
| `getDraft`, `saveDraft` | `{conversation}` / `{conversation, text}` → `{text}` |
| `correctText` | `{text, conversation: qwen ou openai, reportId, review: true}` → proposition `{text, edits, skipped, explanations, reportId}` |
| `decideCorrection` | `{reportId, status: accept ou reject}` valide une proposition prête ou annule le calcul ; événement `accepted` ou `dismissed` |
| `finishCorrection` | `{reportId, status, text?}` confirme l'application, l'annulation ou l'absence de correction |

Un message vaut `{id, role, isSender, timestamp, text, html, state}`. Une réponse
réunit le texte final de chaque message de l'agent et une ligne Markdown par appel
d'outil (`> ▸ **bash** · \`commande\``, suivie de « — failed » en cas d'échec) ; la
réflexion n'est pas affichée. Une erreur du fournisseur (quota, authentification)
est ajoutée en citation et marque la réponse `failed`. `html` est le rendu Goldmark
pour l'agent, ou le texte échappé de l'utilisateur ; aucune ressource n'est chargée
et seuls les liens HTTP(S)/mailto sont actifs. Les formules deviennent des
`<span data-math>` rendus par le worker MathJax local.

L'événement `changed` diffuse des snapshots révisionnés portant `conversation` :
métadonnées et `items` (dernière page, ou seule la bulle qui change pendant le
streaming). `resetRevision` écarte les pages antérieures à une réinitialisation.
`warning` signale un échec d'écriture.

## Correction orthographique

Alt+Tab choisit GPT, Ctrl+Alt+Tab Qwen. Le texte part seul, sans historique.
Le résultat est reconstruit à partir des mots validés ; seules les explications
correspondant aux changements retenus sont affichées. `correctionChanged`
diffuse un compte rendu temporaire (jamais ajouté à l'historique des chats).
Le panneau noir s'ouvre dès le début du traitement, sans voler le focus à Chrome
ou Beeper : logo du modèle animé pendant l'attente et texte original, puis remplacements en rouge
et règle courte par faute. Le champ d'origine reste inchangé pendant cette
prévisualisation : Entrée applique la proposition prête et ferme le panneau,
Échap le ferme sans modification, même pendant le calcul. Ces touches sont
prises en charge dans le champ d'origine et dans le panneau, sans envoyer le
message. Le texte, le curseur et la sélection sont revérifiés avant application.
Sa hauteur suit le contenu, avec défilement quand le
compte rendu dépasse l'espace disponible. Fermer le panneau empêche les mises à jour tardives
de le rouvrir ; une ouverture manuelle rend la conversation normale.

Le host Native Messaging de Chrome passe par le socket privé
`$XDG_RUNTIME_DIR/quickshell-assistant/correction.sock` (`0600`, dossier `0700`).
Il transmet les actions `correct`, `decide`, `wait` et `status` au backend du
panneau déjà lancé. Les attentes de décision sont bornées à vingt secondes et
renouvelées par l'extension. Les anciens clients sans prévisualisation sont refusés.
L'extension n'affiche aucun toast. Son dossier d'installation est copié, et non
lié au Nix store, pour que Chrome conserve un chemin stable entre les versions.
