import QtQuick
import "../../ui/Theme.js" as Theme

// A playful verb ("Pondering…", "Noodling…") swept by a soft glow of the
// model's accent, letter by letter. Each thinking phase draws a new verb, which
// stays until the phase ends. The clock only runs while the label is shown.
Row {
  id: root
  property color accent: Theme.flamingo
  property real pixelSize: 16
  property bool running: visible
  property real time: 0
  readonly property var verbs: [
    "Accomplishing", "Actualizing", "Baking", "Booping", "Brewing", "Calculating",
    "Cerebrating", "Channelling", "Churning", "Coalescing", "Cogitating",
    "Combobulating", "Computing", "Concocting", "Conjuring", "Considering",
    "Contemplating", "Cooking", "Crafting", "Crunching", "Deciphering",
    "Deliberating", "Discombobulating", "Divining", "Elucidating", "Enchanting",
    "Envisioning", "Finagling", "Flibbertigibbeting", "Forging", "Frolicking",
    "Germinating", "Hatching", "Herding", "Honking", "Hustling", "Ideating",
    "Imagining", "Incubating", "Inferring", "Jiving", "Manifesting", "Marinating",
    "Meandering", "Moseying", "Mulling", "Mustering", "Musing", "Noodling",
    "Percolating", "Perusing", "Philosophising", "Pondering", "Pontificating",
    "Puttering", "Puzzling", "Reticulating", "Ruminating", "Scheming",
    "Schlepping", "Shimmying", "Shucking", "Simmering", "Smooshing", "Spelunking",
    "Stewing", "Sussing", "Synthesizing", "Tinkering", "Transmuting", "Unfurling",
    "Unravelling", "Vibing", "Wandering", "Whirring", "Wibbling", "Wizarding",
    "Wrangling"
  ]
  property string verb: ""
  readonly property var letters: Array.from(verb + "…")
  function pickVerb() {
    let next = verb;
    while (next === verb) next = verbs[Math.floor(Math.random() * verbs.length)];
    verb = next;
  }
  objectName: "assistantThinking"
  Accessible.role: Accessible.StaticText
  Accessible.name: verb
  Component.onCompleted: pickVerb()
  onVisibleChanged: if (visible) pickVerb()
  FrameAnimation { running: root.running; onTriggered: root.time += frameTime }
  Repeater {
    model: root.letters
    Text {
      required property string modelData
      required property int index
      // The band crosses the label, then pauses briefly before the next pass.
      readonly property real sweep: (root.time * 0.9) % 1.6 / 1.2 * (root.letters.length + 4) - 2
      readonly property real glow: Math.max(0, 1 - Math.abs(index - sweep) / 3)
      text: modelData
      textFormat: Text.PlainText
      color: Qt.tint(Theme.inactive, Qt.alpha(root.accent, glow))
      font { family: "Ubuntu Nerd Font"; pixelSize: root.pixelSize; weight: Font.Medium }
    }
  }
}
