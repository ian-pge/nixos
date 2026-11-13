import QtQuick
import QtQuick.Controls
import "../../ui/Theme.js" as Theme
import "./AssistantFormat.js" as Format

// HTML comes only from the backend (Goldmark replies, escaped user text);
// the only embedded resources are locally generated formula SVGs.
Item {
  id: root
  property string html: ""
  property var mathRenderer: null
  property string searchQuery: ""
  property real textScale: 1
  property real baseSize: 20
  property color accent: Theme.secondary
  property color textColor: Theme.foreground
  property color selectedTextColor: Theme.background
  property bool renderEnabled: true
  property string displayedHTML: ""
  property string displayedQuery: ""
  property string renderedHTML: ""
  property alias textEdit: editor
  readonly property string copyText: selectedTextWithMath()
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
  function selectedTextWithMath() {
    const before = editor.getText(0, editor.selectionStart);
    let index = (before.match(/\ufffc/g) || []).length;
    const expressions = [];
    const pattern = /<img data-math-source="([A-Za-z0-9+/=]+)" data-display="([01])"/g;
    let match;
    while ((match = pattern.exec(renderedHTML))) {
      const encoded = new Uint8Array(Array.from(match[1], c => c.charCodeAt(0)));
      const decoded = new Uint8Array(Qt.atob(encoded.buffer));
      const tex = decodeURIComponent(Array.from(decoded, byte => "%" + byte.toString(16).padStart(2, "0")).join(""));
      const delimiter = match[2] === "1" ? "$$" : "$";
      expressions.push(delimiter + tex + delimiter);
    }
    return editor.selectedText.replace(/\ufffc/g, () => expressions[index++] || "").replace(/[\u2028\u2029]/g, "\n");
  }
  function activateLink(url) {
    if (/^(https?:\/\/|mailto:)/i.test(url)) openRequested(url);
  }
  function updateDocument() {
    // A live response must not shift the text being selected/copied. Catch up
    // as soon as selection is cleared, retaining only the most recent update.
    if (editor.selectionStart !== editor.selectionEnd) return;
    displayedHTML = html;
    displayedQuery = searchQuery;
    renderedHTML = mathRenderer ? mathRenderer.render(html, textScale * root.baseSize / 20) : html;
  }
  onHtmlChanged: updateDocument()
  onSearchQueryChanged: updateDocument()
  onTextScaleChanged: updateDocument()
  onMathRendererChanged: updateDocument()
  Connections { target: root.mathRenderer; function onRevisionChanged() { Qt.callLater(root.updateDocument); } }
  Component.onCompleted: updateDocument()

  // Intrinsic width is independent of the bubble's constrained width.
  Text {
    id: measurement
    visible: false
    textFormat: Text.RichText
    text: root.stylesheet + root.renderedHTML
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
      objectName: "assistantMarkdownText"
      width: viewport.width
      text: root.stylesheet + Format.highlightHTML(root.renderedHTML, root.displayedQuery, Theme.yellow, Theme.background)
      textFormat: TextEdit.RichText
      wrapMode: TextEdit.Wrap
      readOnly: true
      selectByMouse: true
      persistentSelection: true
      activeFocusOnPress: false
      selectByKeyboard: false
      enabled: root.renderEnabled
      color: root.textColor
      selectedTextColor: root.selectedTextColor
      selectionColor: root.accent
      font { family: "Ubuntu Nerd Font"; pixelSize: root.baseSize * root.textScale }
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
