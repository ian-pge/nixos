import QtQuick
import "./Theme.js" as Theme

// The "/pattern" line of a VimEditing search, with a blinking caret. It is
// visible only while a pattern is typed; the pattern turns red when it has
// no match in the field.
Item {
  id: root
  required property var vim
  property font font: vim.target.font
  property color color: Theme.foreground
  visible: vim.searching
  implicitWidth: prompt.implicitWidth + caret.width + 1
  implicitHeight: prompt.implicitHeight
  Text {
    id: prompt
    objectName: "vimSearchPrompt"
    text: "/" + root.vim.searchPattern
    textFormat: Text.PlainText
    font: root.font
    color: root.vim.searchFound ? root.color : Theme.error
  }
  Rectangle {
    id: caret
    x: prompt.contentWidth + 1; width: 3; height: prompt.height; radius: 1
    color: Theme.textCursor
    opacity: blink.on ? 1 : 0
  }
  Timer {
    id: blink
    property bool on: true
    interval: Math.max(1, Qt.styleHints.cursorFlashTime / 2); repeat: true
    running: root.visible && Qt.styleHints.cursorFlashTime > 0
    onTriggered: on = !on
    onRunningChanged: on = true
  }
  Connections {
    target: root.vim
    function onSearchPatternChanged() { blink.on = true; if (blink.running) blink.restart(); }
  }
}
