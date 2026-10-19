import QtQuick
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Item {
  id: root
  required property var parts
  property bool outgoing: false
  property bool renderEnabled: true
  property real textScale: 1
  property color accent: Theme.sideApplications
  property string searchQuery: ""
  property Item selectionOwner: null
  readonly property string selectedText: selectionOwner?.selectedText || ""
  signal selectedRequested
  signal textSelectionStarted
  signal openRequested(string url)
  signal copyRequested(string url)
  implicitHeight: content.implicitHeight
  implicitWidth: {
    let widest = 0;
    for (const child of content.children)
      widest = Math.max(widest, child.item?.implicitWidth || 0);
    return widest;
  }
  function clearTextSelection() {
    selectionOwner?.clearTextSelection();
    selectionOwner = null;
  }
  Column {
    id: content
    width: root.width
    spacing: 7 * root.textScale
    Repeater {
      model: KeyedListModel {
        rows: root.parts.map((part, index) => Object.assign({
            id: index + ":" + part.kind
          }, part))
      }
      Loader {
        id: part
        required property var row
        width: root.width
        sourceComponent: row.kind === "link" ? card : paragraph
        Component {
          id: card
          BeeperLinkCard {
            link: part.row.link
            outgoing: root.outgoing
            textScale: root.textScale
            accent: root.accent
            searchQuery: root.searchQuery
            onOpenRequested: url => root.openRequested(url)
            onCopyRequested: url => root.copyRequested(url)
          }
        }
        Component {
          id: paragraph
          Text {
            id: prose
            objectName: "beeperLinkParagraph"
            text: part.row.text
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            lineHeight: 1.2
            readonly property string highlights: root.renderEnabled ? Format.highlightText(text, root.searchQuery, Theme.yellow, Theme.background) : ""
            readonly property string selectedText: selection.item?.copyText || ""
            property bool hasSelection: false
            color: highlights ? "transparent" : root.outgoing ? Theme.background : Theme.foreground
            font {
              family: "Ubuntu Nerd Font"
              pixelSize: Theme.beeperFont.body * root.textScale
            }
            function clearTextSelection() {
              selection.item?.deselect();
            }
            Text {
              anchors.fill: parent
              text: prose.highlights
              visible: !!text
              textFormat: Text.RichText
              wrapMode: prose.wrapMode
              font: prose.font
              color: root.outgoing ? Theme.background : Theme.foreground
            }
            HoverHandler {
              id: hover
              enabled: root.renderEnabled
              cursorShape: Qt.IBeamCursor
            }
            Loader {
              id: selection
              anchors.fill: parent
              active: root.renderEnabled && (hover.hovered || prose.hasSelection)
              sourceComponent: TextEdit {
                objectName: "beeperMessageTextSelection"
                readonly property string copyText: selectedText.replace(new RegExp("[\\u2028\\u2029]", "g"), "\n")
                readOnly: true
                selectByMouse: true
                persistentSelection: true
                activeFocusOnPress: false
                text: Format.selectableText(prose.text)
                textFormat: TextEdit.RichText
                wrapMode: prose.wrapMode
                font: prose.font
                color: "transparent"
                selectionColor: root.outgoing ? Theme.background : root.accent
                selectedTextColor: root.outgoing ? root.accent : Theme.selectedForeground
                onSelectedTextChanged: {
                  prose.hasSelection = !!selectedText;
                  if (!selectedText)
                    return;
                  if (root.selectionOwner !== prose) {
                    root.clearTextSelection();
                    root.selectionOwner = prose;
                  }
                  root.textSelectionStarted();
                }
                TapHandler {
                  gesturePolicy: TapHandler.DragThreshold
                  onTapped: root.selectedRequested()
                }
              }
            }
          }
        }
      }
    }
  }
}
