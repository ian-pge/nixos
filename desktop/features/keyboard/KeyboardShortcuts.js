.pragma library

// These are reference labels, not key bindings. Keep browser J/K in sync with
// home_manager/surfingkeys.js. Vim means the built-in Surfingkeys Ace editor.
function shortcut(plain, shifted, group) {
  return { plain: plain || "", shifted: shifted || "", group: group || "navigation" };
}

var pages = [
  { name: "Clavier", title: "QWERTY-Lafayette", description: "", footer: "", keys: {}, cards: [] },
  {
    name: "Navigateur", title: "Chrome · Surfingkeys",
    description: "Mode normal sur une page web · Échap pour sortir d’un champ · J / K personnalisés",
    keys: {
      "Esc": shortcut("Quitter mode", "", "mode"),
      "E": shortcut("½ page ↑", "Onglet ←", "navigation"),
      "R": shortcut("Recharger", "Onglet →", "navigation"),
      "T": shortcut("Ouvrir URL", "Onglets", "tabs"),
      "I": shortcut("Champ", "Vim", "mode"),
      "S": shortcut("", "Histor. ←", "navigation"),
      "D": shortcut("½ page ↓", "Histor. →", "navigation"),
      "F": shortcut("Suivre lien", "", "navigation"),
      "G": shortcut("gg : début", "Fin de page", "navigation"),
      "H": shortcut("Défiler ←", "", "navigation"),
      "J": shortcut("Défiler ↓", "Onglet →", "tabs"),
      "K": shortcut("Défiler ↑", "Onglet ←", "tabs"),
      "L": shortcut("Défiler →", "", "navigation"),
      "X": shortcut("Fermer", "Rouvrir", "tabs"),
      "V": shortcut("Mode visuel", "", "mode"),
      "N": shortcut("Résultat +", "Résultat −", "search"),
      "Y": shortcut("yy : URL", "", "edit"),
      "/": shortcut("Chercher", "Aide (?)", "search")
    },
    cards: [
      { title: "ONGLETS & ADRESSE", group: "tabs", entries: [
        ["Ctrl+l", "Focus barre d’adresse"], ["Ctrl+t / Ctrl+w", "Nouvel onglet / fermer"],
        ["g0 / g$", "Premier / dernier onglet"], ["yt / << / >>", "Dupliquer / déplacer l’onglet"]
      ] },
      { title: "LIENS & SAISIE", group: "navigation", entries: [
        ["f → lettres", "Cliquer le lien ou bouton"], ["gf / af → lettres", "Lien nouvel onglet : fond / actif"],
        ["gi / i → lettres", "Premier champ / choisir un champ"], ["Ctrl+i dans un champ", "Ouvrir l’éditeur Vim"]
      ] },
      { title: "MODES & RECHERCHE", group: "mode", entries: [
        ["/ → texte → Entrée", "Chercher ; n / N pour naviguer"], ["v → v → y", "Curseur texte → sélection → copie"],
        ["Alt+i / Échap", "Laisser les touches au site / retour"], ["Alt+s", "Désactiver / réactiver sur ce site"]
      ] }
    ],
    footer: "Minuscules : action du haut · Maj : action du bas · gg et yy sont des séquences · Sur chrome://, utiliser les raccourcis Chrome"
  },
  {
    name: "Vim", title: "Vim · Éditeur de saisie Surfingkeys",
    description: "Ctrl+i dans un champ pour ouvrir · i pour écrire · Échap pour les commandes · :wq pour reporter le texte et fermer",
    keys: {
      "Esc": shortcut("Mode normal", "", "mode"),
      "0": shortcut("Début de ligne", "", "navigation"),
      "4": shortcut("", "$ : fin", "navigation"),
      "W": shortcut("Mot suivant", "", "navigation"),
      "E": shortcut("Fin du mot", "", "navigation"),
      "R": shortcut("Rempl. 1 car.", "Remplacer", "edit"),
      "Y": shortcut("Copier", "", "edit"),
      "U": shortcut("Annuler", "", "edit"),
      "I": shortcut("Insérer avant", "Début ligne", "mode"),
      "O": shortcut("Ligne ↓", "Ligne ↑", "mode"),
      "P": shortcut("Coller après", "Coller avant", "edit"),
      "A": shortcut("Insérer après", "Fin de ligne", "mode"),
      "S": shortcut("Changer car.", "Ligne", "edit"),
      "D": shortcut("d + mouv.", "Effacer fin", "edit"),
      "C": shortcut("c + mouv.", "Changer fin", "edit"),
      "F": shortcut("Caractère →", "Caractère ←", "search"),
      "G": shortcut("gg : début", "Fin du texte", "navigation"),
      "H": shortcut("Curseur ←", "", "navigation"),
      "J": shortcut("Curseur ↓", "Joindre", "navigation"),
      "K": shortcut("Curseur ↑", "", "navigation"),
      "L": shortcut("Curseur →", "", "navigation"),
      "X": shortcut("Effacer car.", "Effacer avant", "edit"),
      "V": shortcut("Sélection", "Lignes", "mode"),
      "B": shortcut("Mot préc.", "", "navigation"),
      "N": shortcut("Résultat +", "Résultat −", "search"),
      "/": shortcut("Chercher →", "Chercher ←", "search"),
      ".": shortcut("Répéter action", ": commande", "edit")
    },
    cards: [
      { title: "ÉCRIRE & VALIDER", group: "mode", entries: [
        ["i / a / o", "Insérer avant / après / nouvelle ligne"], ["Échap", "Revenir au mode normal"],
        [":wq → Entrée", "Reporter dans le champ et fermer"], [":q → Entrée", "Fermer sans reporter les changements"]
      ] },
      { title: "ÉDITER", group: "edit", entries: [
        ["dd / yy / p", "Couper ligne / copier ligne / coller"], ["dw / cw / ciw", "Effacer mot / changer / mot entier"],
        ["u / Ctrl+r", "Annuler / rétablir"], ["v → déplacement → y", "Sélectionner puis copier"]
      ] },
      { title: "SE DÉPLACER", group: "navigation", entries: [
        ["h j k l", "Gauche / bas / haut / droite"], ["w / b / e", "Mot suivant / précédent / fin"],
        ["0 / $ · gg / G", "Début / fin de ligne · du texte"], ["/mot → Entrée · n / N", "Chercher · suivant / précédent"]
      ] }
    ],
    footer: "Commandes en mode normal · 3w = avancer de 3 mots · dd = couper une ligne · : = Maj + . sur Lafayette · :wq ne clique pas sur Envoyer"
  }
];

function page(index) {
  return pages[index] || pages[0];
}

function nextPage(index, step) {
  return (index + step + pages.length) % pages.length;
}
