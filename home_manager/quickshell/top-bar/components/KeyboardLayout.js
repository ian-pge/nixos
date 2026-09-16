.pragma library

// HHKB physical geometry; Lafayette 0.9 character levels from the pinned XKB map.
// Levels: base, Shift, AltGr, Shift+AltGr, ★ then key, ★ then Shift+key.
// ★ is a one-shot level latch on the physical semicolon key, not Compose.
// Dotted circles mark dead accents. Firmware-specific Fn mappings are unchanged.
var layoutName = "QWERTY-Lafayette";
var layoutDescription = "★ = touche ; à droite de L · appuyer puis relâcher · AltGr = symboles";
var characterLevels = {
  "0": ["0",")","₀","⁰","°",""],
  "1": ["1","!","₁","¹","¡","„"],
  "2": ["2","@","₂","²","«","“"],
  "3": ["3","#","₃","³","»","”"],
  "4": ["4","$","₄","⁴","£","¢"],
  "5": ["5","%","₅","⁵","€","‰"],
  "6": ["6","^","₆","⁶","¥",""],
  "7": ["7","&","₇","⁷","¤",""],
  "8": ["8","*","₈","⁸","§",""],
  "9": ["9","(","₉","⁹","¶",""],
  "-": ["-","_","","","—",""],
  "=": ["=","+","","","≠","±"],
  "Q": ["q","Q","^","◌̂","æ","Æ"],
  "W": ["w","W","<","≤","é","É"],
  "E": ["e","E",">","≥","è","È"],
  "R": ["r","R","$","¤★","",""],
  "T": ["t","T","%","‰","",""],
  "Y": ["y","Y","@","◌̊","",""],
  "U": ["u","U","&","","ù","Ù"],
  "I": ["i","I","*","×","ï","Ï"],
  "O": ["o","O","'","◌́","œ","Œ"],
  "P": ["p","P","`","◌̀","",""],
  "[": ["[","{","","","",""],
  "]": ["]","}","","","",""],
  "A": ["a","A","{","◌̌","à","À"],
  "S": ["s","S","(","⁽","ß","ẞ"],
  "D": ["d","D",")","⁾","ê","Ê"],
  "F": ["f","F","}","◌̇","-","ª"],
  "G": ["g","G","=","≠","–","–"],
  "H": ["h","H","\\","◌̸","ŷ","Ŷ"],
  "J": ["j","J","+","±","û","Û"],
  "K": ["k","K","-","◌̄","î","Î"],
  "L": ["l","L","/","÷","ô","Ô"],
  ";": ["★","★","\"","◌̋","◌̈",""],
  "'": ["'","\"","","","",""],
  "Z": ["z","Z","~","◌̃","â","Â"],
  "X": ["x","X","[","◌̦","×",""],
  "C": ["c","C","]","◌̨","ç","Ç"],
  "V": ["v","V","_","–","_","_"],
  "B": ["b","B","#","","—","—"],
  "N": ["n","N","|","¦","ñ","Ñ"],
  "M": ["m","M","!","¬","µ","º"],
  ",": [",",";",";","◌̧","·","•"],
  ".": [".",":",":",":","…",""],
  "/": ["/","?","?","◌̆","¿","÷"],
  "\\": ["\\","|","","","",""],
  "`": ["`","~","","","",""]
};

function key(label, action, group, units) {
  var symbols = characterLevels[label]
    || (/^[A-Z]$/.test(label) ? [label.toLowerCase(), label] : []);
  return { label: label, action: action || "", group: group || "",
    units: units || 1, symbols: symbols,
    // Keep the complete XKB map for validation, but omit uppercase letters
    // (including accented capitals) from the visual reference.
    displaySymbols: symbols.map(function(symbol, index) {
      return index % 2 === 1 && symbol !== symbol.toLowerCase() ? "" : symbol;
    }) };
}

var rows = [
  [key("Esc", "Verrouiller", "system"),
   key("1", "Bureau 1", "workspace"), key("2", "Bureau 2", "workspace"),
   key("3", "Bureau 3", "workspace"), key("4", "Bureau 4", "workspace"),
   key("5", "Bureau 5", "workspace"), key("6", "Bureau 6", "workspace"),
   key("7", "Bureau 7", "workspace"), key("8", "Bureau 8", "workspace"),
   key("9"), key("0"), key("-"), key("="), key("\\"), key("`")],
  [key("Tab", "Dictée", "system", 1.5),
   key("Q", "Config Nix", "app"), key("W", "Fermer", "window"),
   key("E", "Calendrier", "system"), key("R", "Audio", "system"),
   key("T"), key("Y"), key("U", "Mises à jour", "system"),
   key("I"), key("O"), key("P", "Onglets", "app"),
   key("["), key("]"), key("Backspace", "", "", 1.5)],
  [key("Control", "", "modifier", 1.75),
   key("A", "Lanceur", "app"), key("S", "LLM", "workspace"),
   key("D", "Chat", "workspace"), key("F", "Fichiers", "app"),
   key("G", "Chrome", "app"), key("H", "Focus ←", "window"),
   key("J", "Focus ↓", "window"), key("K", "Focus ↑", "window"),
   key("L", "Focus →", "window"), key(";"),
   key("'", "Cette aide", "help"), key("Return", "Terminal", "app", 2.25)],
  [key("Shift", "", "modifier", 2.25),
   key("Z", "Scinder", "window"), key("X", "Calculatrice", "app"),
   key("C", "Musique", "workspace"), key("V", "Notes", "workspace"),
   key("B", "Bluetooth", "system"), key("N", "Wi-Fi", "system"),
   key("M", "Agenda", "workspace"), key(","), key("."), key("/"),
   key("Shift", "", "modifier", 1.75), key("Delete")],
  [key("", "", "gap", 1.5), key("Alt"), key("⌘ Cmd", "Maintenir", "help", 1.5),
   key("Space", "Agrandir la fenêtre", "window", 6),
   key("AltGr", "", "level3", 1.5), key("Fn"), key("", "", "gap", 2.5)]
];
