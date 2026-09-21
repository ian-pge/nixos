import QtQuick
import "Theme.js" as Theme
import "KeyboardLayout.js" as KeyboardLayout
import "KeyboardShortcuts.js" as KeyboardShortcuts

Rectangle {
  id: root
  implicitWidth: 1206
  implicitHeight: content.implicitHeight + 48
  width: implicitWidth
  height: implicitHeight
  radius: 26
  color: "transparent"
  border.width: 0
  property int pageIndex: 0
  readonly property var page: KeyboardShortcuts.page(pageIndex)
  readonly property bool layoutPage: pageIndex === 0

  function cyclePage(step) {
    pageIndex = KeyboardShortcuts.nextPage(pageIndex, step);
  }

  function accent(group) {
    switch (group) {
    case "app": return Theme.sideBluetooth;
    case "workspace": return Theme.sideSystem;
    case "window": return Theme.sideDisk;
    case "system": return Theme.sideNotifications;
    case "help": return Theme.sideWeather;
    case "level3": return Theme.sideDate;
    case "navigation": return Theme.sideApplications;
    case "tabs": return Theme.sideWeather;
    case "edit": return Theme.sideDisk;
    case "mode": return Theme.sideSystem;
    case "search": return Theme.sideDate;
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
          text: "HHKB  /  " + root.page.title
          color: Theme.foreground
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 27
          font.weight: Font.DemiBold
        }
        Text {
          text: root.layoutPage ? KeyboardLayout.layoutDescription : root.page.description
          color: Theme.secondary
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 14
        }
      }
    }

    Row {
      spacing: 10
      Repeater {
        model: KeyboardShortcuts.pages
        delegate: Rectangle {
          required property int index
          required property var modelData
          width: tabLabel.implicitWidth + 30
          height: 32
          radius: 16
          color: root.pageIndex === index ? Theme.action : Theme.surfaceRaised
          Text {
            id: tabLabel
            anchors.centerIn: parent
            text: modelData.name
            color: root.pageIndex === parent.index ? Theme.background : Theme.foreground
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 14
            font.weight: Font.DemiBold
          }
        }
      }
      Text {
        height: 32
        verticalAlignment: Text.AlignVCenter
        text: "Tab : suivant  ·  Maj+Tab : précédent  ·  Maintenir Cmd+'"
        color: Theme.secondary
        font.family: "Ubuntu Nerd Font"
        font.pixelSize: 13
      }
    }

    Row {
      visible: root.layoutPage
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
          font.family: "Ubuntu Nerd Font"
          font.pixelSize: 13
        }
      }
      Text {
        text: "Action en bas : ⌘ Cmd + touche"
        color: Theme.sideWeather
        font.family: "Ubuntu Nerd Font"
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
              readonly property var shortcut: root.layoutPage ? null : root.page.keys[modelData.label] || null
              readonly property color accentColor: root.accent(root.layoutPage ? modelData.group : shortcut?.group || "")
              readonly property bool hasAction: root.layoutPage ? !!modelData.action : shortcut !== null
              width: modelData.units * 76 - 6
              height: 78
              radius: 10
              color: modelData.group === "gap" ? "transparent" : Theme.surfaceRaised
              border.width: modelData.group === "gap" ? 0 : 1
              border.color: hasAction ? accentColor : Theme.surfaceSelected

              Text {
                visible: root.layoutPage && keycap.modelData.symbols.length === 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 11
                text: keycap.modelData.label
                color: keycap.modelData.action || keycap.modelData.group === "level3"
                  ? keycap.accentColor : Theme.foreground
                font.family: "Ubuntu Nerd Font"
                font.pixelSize: keycap.modelData.label.length > 4 ? 14 : 20
                font.weight: Font.DemiBold
              }
              Repeater {
                model: root.layoutPage ? keycap.modelData.symbols.length : 0
                delegate: Text {
                  required property int index
                  // Base left, AltGr right, one-shot ★ in the middle; actions stay
                  // on a separate line so symbols never imply a Cmd chord.
                  x: index < 2 ? 7 : index < 4 ? keycap.width - width - 7 : (keycap.width - width) / 2
                  y: index % 2 === 0 ? 28 : 3
                  text: keycap.modelData.displaySymbols[index] || ""
                  color: index >= 4 ? Theme.sideWeather : index >= 2 ? Theme.sideDate
                    : index === 0 ? Theme.foreground : Theme.secondary
                  font.family: "Ubuntu Nerd Font"
                  font.pixelSize: 17
                  font.weight: index === 0 ? Font.DemiBold : Font.Medium
                }
              }
              Text {
                visible: root.layoutPage
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 5
                anchors.rightMargin: 5
                anchors.bottomMargin: 8
                text: keycap.modelData.action
                color: keycap.accentColor
                horizontalAlignment: Text.AlignHCenter
                font.family: "Ubuntu Nerd Font"
                font.pixelSize: 11
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 9
              }
              Text {
                visible: !root.layoutPage && keycap.modelData.group !== "gap"
                anchors.top: parent.top
                anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
                text: keycap.modelData.symbols[0] || keycap.modelData.label
                color: keycap.hasAction ? Theme.foreground : Theme.inactive
                font.family: "Ubuntu Nerd Font"
                font.pixelSize: keycap.modelData.label.length > 4 ? 13 : 18
                font.weight: Font.DemiBold
              }
              Column {
                visible: !root.layoutPage && keycap.shortcut !== null
                x: 4
                y: 33
                width: parent.width - 8
                spacing: 3
                Repeater {
                  model: keycap.shortcut ? [keycap.shortcut.plain, keycap.shortcut.shifted] : []
                  delegate: Text {
                    required property int index
                    required property string modelData
                    width: parent.width
                    height: 16
                    text: modelData ? (index === 1 ? "⇧ " : "") + modelData : ""
                    color: index === 0 ? keycap.accentColor : Theme.foreground
                    horizontalAlignment: Text.AlignHCenter
                    font.family: "Ubuntu Nerd Font"
                    font.pixelSize: 11
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: 8
                  }
                }
              }
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      text: root.layoutPage
        ? "★ puis w → é · e → è · a → à · c → ç · d → ê · ★ puis ★ puis e → ë   |   ; = Shift + ,   : = Shift + .   |   ◌ = accent mort"
        : root.page.footer
      color: Theme.secondary
      font.family: "Ubuntu Nerd Font"
      font.pixelSize: 12
    }

    Row {
      visible: root.layoutPage
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
            font.family: "Ubuntu Nerd Font"
            font.pixelSize: 12
          }
        }
      }
    }

    Row {
      visible: !root.layoutPage
      width: parent.width
      spacing: 12
      Repeater {
        model: root.page.cards || []
        delegate: Rectangle {
          required property var modelData
          width: (content.width - 24) / 3
          height: referenceContent.implicitHeight + 24
          radius: 12
          color: Theme.surface
          Column {
            id: referenceContent
            x: 12
            y: 12
            width: parent.width - 24
            spacing: 8
            Text {
              text: modelData.title
              color: root.accent(modelData.group)
              font.family: "Ubuntu Nerd Font"
              font.pixelSize: 12
              font.weight: Font.DemiBold
            }
            Repeater {
              model: modelData.entries
              delegate: Column {
                required property var modelData
                width: parent.width
                spacing: 2
                Text {
                  text: parent.modelData[0]
                  color: Theme.foreground
                  font.family: "Ubuntu Nerd Font"
                  font.pixelSize: 12
                  font.weight: Font.DemiBold
                }
                Text {
                  width: parent.width
                  text: parent.modelData[1]
                  color: Theme.secondary
                  font.family: "Ubuntu Nerd Font"
                  font.pixelSize: 12
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }
      }
    }

  }
}
