import QtQuick
import QtQuick.Shapes
import Quickshell

// Five isolated, deterministic UI screenshots. No desktop services or accounts.
ShellRoot {
  id: root
  property int variant: 0
  readonly property bool compact: Quickshell.env("QS_NOTCH_COMPACT") === "1"
  readonly property string destination: Quickshell.env("QS_NOTCH_PREVIEW_DIR")
  readonly property var names: compact
    ? ["Fil discret", "Rose léger", "Horloge en tête", "Météo lisible", "Pastille horaire"]
    : ["Épuré", "Horloge dominante", "Symétrique", "Trois colonnes", "Accent rose"]
  readonly property var heights: compact ? [26, 28, 28, 30, 30] : [56, 78, 76, 78, 66]
  readonly property var descriptions: compact ? [
    "26 px de haut · Le plus discret, sans séparateurs.",
    "28 px de haut · Des accents roses, une seule ligne.",
    "28 px de haut · L’heure d’abord, chiffres monospace.",
    "30 px de haut · La météo en toutes lettres, sans deuxième ligne.",
    "30 px de haut · Une petite pastille rose pour l’heure."
  ] : [
    "Une ligne légère, l’heure en évidence.",
    "Une grande horloge, date et météo sur deux lignes.",
    "L’heure au centre, date et météo de chaque côté.",
    "Trois informations clairement séparées.",
    "Une touche rose pour mettre l’heure au premier plan."
  ]
  readonly property var files: compact
    ? ["01-fil-discret.png", "02-rose-leger.png", "03-horloge-en-tete.png", "04-meteo-lisible.png", "05-pastille-horaire.png"]
    : ["01-epure.png", "02-horloge.png", "03-symetrique.png", "04-colonnes.png", "05-accent-rose.png"]
  function capture() {
    if (!art.grabToImage(result => {
      if (!result.saveToFile(destination + "/" + files[variant])) { Qt.exit(1); return; }
      console.log("Saved", files[variant]);
      if (variant === 4) Qt.exit(0);
      else { variant++; settle.restart(); }
    }, Qt.size(1600, 416))) Qt.exit(1);
  }
  Component.onCompleted: {
    Quickshell.watchFiles = false;
    if (!destination || Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") { Qt.exit(1); return; }
    settle.start();
  }
  Timer { id: settle; interval: 600; onTriggered: root.capture() }

  component Label: Text {
    color: "#e9e9ee"
    font.family: "Ubuntu"
    font.pixelSize: 18
    textFormat: Text.PlainText
  }
  component WeatherIcon: Loader {
    width: 24; height: 24
    property color ink: "#a8c9ef"
    source: "file://" + Quickshell.shellDir + "/../ui/Icon.qml"
    onLoaded: { item.name = "cloud-drizzle"; item.size = 24; item.color = Qt.binding(() => ink); }
  }
  component Divider: Rectangle {
    width: 1; height: 28; color: "#35353d"
    anchors.verticalCenter: parent.verticalCenter
  }
  Window {
    visible: true
    width: 1000; height: 260
    Item {
      id: art
      anchors.fill: parent
      Image {
        anchors.fill: parent
        source: "file:///nix/store/187wy2p0k0lbzx9r5vnmk5pda2w0lmw3-wallpaper.png"
        fillMode: Image.PreserveAspectCrop
      }
      Rectangle { anchors.fill: parent; color: "#66080c14" }
      Column {
        x: 32; y: 24; spacing: 7
        Label { text: "0" + (root.variant + 1) + "  /  " + root.names[root.variant]; font.pixelSize: 24; font.bold: true }
        Label { text: root.descriptions[root.variant]; font.pixelSize: 14; color: "#c6c8d0" }
      }
      Item {
        id: notch
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: root.compact ? [284, 318, 308, 356, 304][root.variant]
          : [414, 442, 466, 462, 450][root.variant]
        height: root.heights[root.variant]
        readonly property real corner: root.compact ? 8 : 15
        // Same black backdrop and concave shoulders as the installed notch.
        Shape {
          anchors.fill: parent
          transform: Scale { origin.y: notch.height / 2; yScale: -1 }
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            strokeColor: "transparent"; strokeWidth: 0; fillColor: "#000000"
            startX: 0; startY: 0
            PathLine { x: notch.width; y: 0 }
            PathCubic { x: notch.width - notch.corner; y: notch.corner; control1X: notch.width - 0.5523 * notch.corner; control1Y: 0; control2X: notch.width - notch.corner; control2Y: 0.4477 * notch.corner }
            PathLine { x: notch.width - notch.corner; y: notch.height - notch.corner }
            PathCubic { x: notch.width - 2 * notch.corner; y: notch.height; control1X: notch.width - notch.corner; control1Y: notch.height - 0.4477 * notch.corner; control2X: notch.width - 1.4477 * notch.corner; control2Y: notch.height }
            PathLine { x: 2 * notch.corner; y: notch.height }
            PathCubic { x: notch.corner; y: notch.height - notch.corner; control1X: 1.4477 * notch.corner; control1Y: notch.height; control2X: notch.corner; control2Y: notch.height - 0.4477 * notch.corner }
            PathLine { x: notch.corner; y: notch.corner }
            PathCubic { x: 0; y: 0; control1X: notch.corner; control1Y: 0.4477 * notch.corner; control2X: 0.5523 * notch.corner; control2Y: 0 }
          }
        }
        Loader {
          anchors.centerIn: parent
          sourceComponent: root.compact
            ? [slimMinimal, slimPink, slimClock, slimWeather, slimAccent][root.variant]
            : [minimal, dominant, symmetric, columns, accent][root.variant]
        }
      }
    }
  }
  Component {
    id: slimMinimal
    Row {
      spacing: 14
      Label { text: "mer. 21 oct."; font.pixelSize: 14; color: "#afb1ba"; anchors.verticalCenter: parent.verticalCenter }
      Label { text: "12:00"; font.pixelSize: 18; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
      Row {
        spacing: 5; anchors.verticalCenter: parent.verticalCenter
        WeatherIcon { width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
        Label { text: "11°"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }
  Component {
    id: slimPink
    Row {
      spacing: 12
      Label { text: "Mer. 21 oct."; font.pixelSize: 14; color: "#f5bde6"; anchors.verticalCenter: parent.verticalCenter }
      Divider { height: 12 }
      Label { text: "12:00"; font.pixelSize: 20; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
      Divider { height: 12 }
      Row {
        spacing: 5; anchors.verticalCenter: parent.verticalCenter
        WeatherIcon { width: 17; height: 17; ink: "#f5bde6"; anchors.verticalCenter: parent.verticalCenter }
        Label { text: "11°"; font.pixelSize: 14; color: "#f5bde6"; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }
  Component {
    id: slimClock
    Row {
      spacing: 12
      Label { text: "12:00"; font.family: "DejaVu Sans Mono"; font.pixelSize: 19; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
      Divider { height: 12 }
      Label { text: "MER 21 OCT"; font.pixelSize: 13; font.letterSpacing: 0.5; color: "#b6bac8"; anchors.verticalCenter: parent.verticalCenter }
      Row {
        spacing: 5; anchors.verticalCenter: parent.verticalCenter
        WeatherIcon { width: 17; height: 17; ink: "#8bd5ca"; anchors.verticalCenter: parent.verticalCenter }
        Label { text: "11°"; font.pixelSize: 14; color: "#8bd5ca"; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }
  Component {
    id: slimWeather
    Row {
      spacing: 14
      Label { text: "21 octobre"; font.pixelSize: 15; color: "#afb1ba"; anchors.verticalCenter: parent.verticalCenter }
      Label { text: "12:00"; font.pixelSize: 20; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
      Divider { height: 14 }
      Row {
        spacing: 5; anchors.verticalCenter: parent.verticalCenter
        WeatherIcon { width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter }
        Label { text: "Pluie · 11°"; font.pixelSize: 14; color: "#bed1eb"; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }
  Component {
    id: slimAccent
    Row {
      spacing: 13
      Label { text: "mer. 21 oct."; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
      Rectangle {
        width: 66; height: 24; radius: 7; color: "#f5bde6"
        Label { anchors.centerIn: parent; text: "12:00"; font.pixelSize: 18; font.bold: true; color: "#000000" }
      }
      Row {
        spacing: 5; anchors.verticalCenter: parent.verticalCenter
        WeatherIcon { width: 17; height: 17; ink: "#f5bde6"; anchors.verticalCenter: parent.verticalCenter }
        Label { text: "11°"; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }
  Component {
    id: minimal
    Row {
      spacing: 20
      Label { text: "mer. 21 oct."; color: "#c6c6cd"; anchors.verticalCenter: parent.verticalCenter }
      Label { text: "12:00"; font.pixelSize: 27; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
      Row {
        spacing: 7; anchors.verticalCenter: parent.verticalCenter
        WeatherIcon { anchors.verticalCenter: parent.verticalCenter }
        Label { text: "11°"; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }
  Component {
    id: dominant
    Row {
      spacing: 22
      Label { text: "12:00"; font.pixelSize: 39; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
      Column {
        spacing: 5; anchors.verticalCenter: parent.verticalCenter
        Label { text: "Mercredi 21 octobre"; font.pixelSize: 16; color: "#f5bde6" }
        Row {
          spacing: 7
          WeatherIcon { width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter }
          Label { text: "11°  ·  Pluie légère"; color: "#b4b7c2"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
        }
      }
    }
  }
  Component {
    id: symmetric
    Row {
      spacing: 26
      Column {
        width: 91; spacing: 3; anchors.verticalCenter: parent.verticalCenter
        Label { text: "MERCREDI"; font.pixelSize: 10; font.letterSpacing: 1.4; color: "#999da9"; anchors.horizontalCenter: parent.horizontalCenter }
        Label { text: "21 octobre"; font.pixelSize: 16; anchors.horizontalCenter: parent.horizontalCenter }
      }
      Label { text: "12:00"; font.pixelSize: 35; font.bold: true; color: "#f5bde6"; anchors.verticalCenter: parent.verticalCenter }
      Column {
        width: 91; spacing: 2; anchors.verticalCenter: parent.verticalCenter
        Row {
          anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
          WeatherIcon { anchors.verticalCenter: parent.verticalCenter }
          Label { text: "11°"; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
        }
        Label { text: "Pluie légère"; font.pixelSize: 11; color: "#999da9"; anchors.horizontalCenter: parent.horizontalCenter }
      }
    }
  }
  Component {
    id: columns
    Row {
      spacing: 22
      Column {
        width: 94; spacing: 5
        Label { text: "DATE"; font.pixelSize: 10; font.letterSpacing: 2; color: "#b7bdf8" }
        Label { text: "21 OCT."; font.pixelSize: 22; font.bold: true }
      }
      Divider {}
      Column {
        width: 90; spacing: 5
        Label { text: "HEURE"; font.pixelSize: 10; font.letterSpacing: 2; color: "#f5bde6" }
        Label { text: "12:00"; font.pixelSize: 22; font.bold: true }
      }
      Divider {}
      Column {
        width: 82; spacing: 5
        Label { text: "MÉTÉO"; font.pixelSize: 10; font.letterSpacing: 2; color: "#8bd5ca" }
        Row {
          spacing: 7
          WeatherIcon { ink: "#8bd5ca"; anchors.verticalCenter: parent.verticalCenter }
          Label { text: "11°"; font.pixelSize: 22; font.bold: true }
        }
      }
    }
  }
  Component {
    id: accent
    Row {
      spacing: 22
      Column {
        anchors.verticalCenter: parent.verticalCenter; spacing: 2
        Label { text: "Mercredi"; font.pixelSize: 12; color: "#a2a5b0" }
        Label { text: "21 octobre"; font.pixelSize: 17 }
      }
      Rectangle {
        width: 106; height: 38; radius: 12
        color: "#f5bde6"
        Label { anchors.centerIn: parent; text: "12:00"; font.pixelSize: 26; font.bold: true; color: "#090909" }
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter; spacing: 7
        WeatherIcon { ink: "#f5bde6"; anchors.verticalCenter: parent.verticalCenter }
        Label { text: "11°"; font.pixelSize: 21; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }
}
