import QtQuick
import QtQuick.Controls
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

// Only the backend's resource-free Markdown HTML enters this component.
Item {
  id: root
  property string html: ""
  property string searchQuery: ""
  property real textScale: 1
  property color accent: Theme.secondary
  property bool renderEnabled: true
  property string displayedHTML: ""
  property string displayedQuery: ""
  property alias textEdit: editor
  readonly property string copyText: editor.selectedText.replace(/[\u2028\u2029]/g, "\n")
  readonly property bool overflowing: editor.contentWidth > viewport.width + 1
  readonly property string stylesheet: "<style>"
    + "p { margin-top: 6px; margin-bottom: 8px; line-height: 120%; }"
    + "h1,h2,h3,h4,h5,h6 { margin-top: 12px; margin-bottom: 6px; }"
    + "h1 { font-size: 140%; } h2 { font-size: 125%; } h3 { font-size: 110%; }"
    + "pre { white-space: pre-wrap; font-family: monospace; background-color: " + Theme.surfaceRaised + "; margin-top: 8px; margin-bottom: 8px; }"
    + "code { font-family: monospace; background-color: " + Theme.surfaceRaised + "; }"
    + "a { color: " + accent + "; }"
    + "table { border-collapse: collapse; } th,td { padding: 6px; border: 1px solid " + Theme.inactive + "; }"
    + "blockquote { margin-left: 16px; color: " + Theme.secondary + "; }"
    + "</style>"
  implicitWidth: measurement.implicitWidth
  implicitHeight: editor.implicitHeight + (overflowing ? 12 : 0)
  signal selectedRequested()
  signal textSelectionStarted()
  signal openRequested(string url)

  function clearTextSelection() { editor.deselect(); updateDocument(); }
  function activateLink(url) {
    if (/^(https?:\/\/|mailto:)/i.test(url)) openRequested(url);
  }
  function updateDocument() {
    // A live response must not shift the text being selected/copied. Catch up
    // as soon as selection is cleared, retaining only the most recent update.
    if (editor.selectionStart !== editor.selectionEnd) return;
    if (displayedHTML === html && displayedQuery === searchQuery) return;
    displayedHTML = html;
    displayedQuery = searchQuery;
  }
  onHtmlChanged: updateDocument()
  onSearchQueryChanged: updateDocument()
  Component.onCompleted: updateDocument()

  // Intrinsic width is independent of the bubble's constrained width.
  Text {
    id: measurement
    visible: false
    textFormat: Text.RichText
    text: root.stylesheet + root.displayedHTML
    font: editor.font
  }
  Flickable {
    id: viewport
    anchors.fill: parent
    contentWidth: Math.max(width, editor.contentWidth)
    contentHeight: editor.implicitHeight
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    acceptedButtons: Qt.NoButton
    clip: true
    ScrollBar.horizontal: ScrollBar { policy: root.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
    TextEdit {
      id: editor
      objectName: "beeperMarkdownText"
      width: viewport.width
      text: root.stylesheet + Format.highlightMarkdownHTML(root.displayedHTML, root.displayedQuery, Theme.yellow, Theme.background)
      textFormat: TextEdit.RichText
      wrapMode: TextEdit.Wrap
      readOnly: true
      selectByMouse: true
      persistentSelection: true
      activeFocusOnPress: false
      selectByKeyboard: false
      enabled: root.renderEnabled
      color: Theme.foreground
      selectedTextColor: Theme.background
      selectionColor: root.accent
      font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.body * root.textScale }
      onLinkActivated: link => root.activateLink(link)
      onSelectedTextChanged: {
        if (selectedText) root.textSelectionStarted();
        else Qt.callLater(root.updateDocument);
      }
      HoverHandler { cursorShape: editor.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
      TapHandler { gesturePolicy: TapHandler.DragThreshold; onTapped: root.selectedRequested() }
    }
  }
}
