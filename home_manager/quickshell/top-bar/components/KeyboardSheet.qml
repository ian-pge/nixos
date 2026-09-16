import QtQuick
import "Theme.js" as Theme
import "KeyboardLayout.js" as KeyboardLayout

Rectangle {
  id: root
  implicitWidth: 1206
  implicitHeight: content.implicitHeight + 48
  width: implicitWidth
  height: implicitHeight
  radius: 26
  color: "transparent"
  border.width: 0

  function accent(group) {
    switch (group) {
    case "app": return Theme.sideBluetooth;
    case "workspace": return Theme.sideSystem;
    case "window": return Theme.sideDisk;
    case "system": return Theme.sideNotifications;
    case "help": return Theme.sideWeather;
    case "level3": return Theme.sideDate;
    default: return Theme.secondary;
    }
  }

  Column {
    id: content
    x: 36
    y: 24
    width: parent.width - 72
    spacing: 14

    Item {
      width: parent.width
      height: 58
      Column {
        spacing: 7
        Text {
          text: "HHKB  /  " + KeyboardLayout.layoutName
          color: Theme.foreground
          font.family: "Inter"
          font.pixelSize: 27
          font.weight: Font.DemiBold
        }
        Text {
          text: KeyboardLayout.layoutDescription
          color: Theme.secondary
          font.family: "Inter"
          font.pixelSize: 14
        }
      }
    }

    Row {
      spacing: 24
      Repeater {
        model: [
          { label: "↙ Sans modificateur", color: Theme.foreground },
          { label: "↖ Shift", color: Theme.secondary },
          { label: "Centre : ★ / ★ puis Shift", color: Theme.sideWeather },
          { label: "↘ AltGr", color: Theme.sideDate },
          { label: "↗ Shift + AltGr", color: Theme.sideDate }
        ]
        delegate: Text {
          required property var modelData
          text: modelData.label
          color: modelData.color
          font.family: "Inter"
          font.pixelSize: 13
        }
      }
      Text {
        text: "Action en bas : ⌘ Cmd + touche"
        color: Theme.sideWeather
        font.family: "Inter"
        font.pixelSize: 13
      }
    }

    Column {
      spacing: 6
      Repeater {
        model: KeyboardLayout.rows
        delegate: Row {
          required property var modelData
          spacing: 6
          Repeater {
            model: modelData
            delegate: Rectangle {
              id: keycap
              required property var modelData
              readonly property color accentColor: root.accent(modelData.group)
              width: modelData.units * 76 - 6
              height: 78
              radius: 10
              color: modelData.group === "gap" ? "transparent"
                : modelData.group === "help" ? Qt.alpha(accentColor, 0.18)
                : Qt.alpha(Theme.surfaceRaised, 0.45)
              border.width: modelData.group === "gap" ? 0 : 1
              border.color: modelData.action ? Qt.alpha(accentColor, 0.4) : Theme.surfaceSelected

              Text {
                visible: keycap.modelData.symbols.length === 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 11
                text: keycap.modelData.label
                color: keycap.modelData.action || keycap.modelData.group === "level3"
                  ? keycap.accentColor : Theme.foreground
                font.family: "Inter"
                font.pixelSize: keycap.modelData.label.length > 4 ? 14 : 20
                font.weight: Font.DemiBold
              }
              Repeater {
                model: keycap.modelData.symbols.length
                delegate: Text {
                  required property int index
                  // Base left, AltGr right, one-shot ★ in the middle; actions stay
                  // on a separate line so symbols never imply a Cmd chord.
                  x: index < 2 ? 7 : index < 4 ? keycap.width - width - 7 : (keycap.width - width) / 2
                  y: index % 2 === 0 ? 28 : 3
                  text: keycap.modelData.displaySymbols[index] || ""
                  color: index >= 4 ? Theme.sideWeather : index >= 2 ? Theme.sideDate
                    : index === 0 ? Theme.foreground : Theme.secondary
                  font.family: "Inter"
                  font.pixelSize: 17
                  font.weight: index === 0 ? Font.DemiBold : Font.Medium
                }
              }
              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                anchors.bottomMargin: 8
                text: keycap.modelData.action
                color: keycap.accentColor
                horizontalAlignment: Text.AlignHCenter
                font.family: "Inter"
                font.pixelSize: 11
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 9
              }
            }
          }
        }
      }
    }

    Text {
      text: "★ puis w → é · e → è · a → à · c → ç · d → ê · ★ puis ★ puis e → ë   |   ; = Shift + ,   : = Shift + .   |   ◌ = accent mort"
      color: Theme.secondary
      font.family: "Inter"
      font.pixelSize: 12
    }

    Row {
      spacing: 28
      Repeater {
        model: [
          { group: "app", title: "Applications" },
          { group: "workspace", title: "Espaces de travail" },
          { group: "window", title: "Fenêtres" },
          { group: "system", title: "Système" }
        ]
        delegate: Row {
          required property var modelData
          spacing: 8
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 7; height: 7; radius: 4
            color: root.accent(parent.modelData.group)
          }
          Text {
            text: parent.modelData.title
            color: Theme.secondary
            font.family: "Inter"
            font.pixelSize: 12
          }
        }
      }
    }

  }
}
