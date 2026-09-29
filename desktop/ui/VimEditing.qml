import QtQuick
import "./Theme.js" as Theme
import "./VimCore.js" as Core

// Vim-style modal editing for one text field: TextArea, TextEdit, TextField
// or TextInput. The logic lives in VimCore.js; this item only translates key
// events, applies edits in place, and draws the normal-mode block cursor and
// the matches of a / search being typed. VimSearchPrompt shows the pattern.
//
// The owner forwards its key presses first and keeps the field read-only
// outside insert mode, so input-method commits, pastes and drops cannot
// type into normal mode:
//   Keys.onPressed: event => { if (vim.handleKeyEvent(event)) return; ... }
//   readOnly: !vim.inserting
// A bare Escape in normal mode is left unaccepted for the owner's own use.
Item {
  id: root
  required property Item target
  property bool active: true
  // Multi-line fields get o, O, J and linewise pastes.
  property bool multiline: true
  // As in Zed: an opaque block, with the character under it redrawn in the
  // field's background color.
  property color cursorColor: Theme.textCursor
  property color cursorTextColor: Theme.surface
  property color matchColor: Theme.searchMatch
  property color currentMatchColor: Theme.searchCurrentMatch
  readonly property alias mode: internal.mode
  readonly property bool inserting: !active || internal.mode === "insert"
  // The character under the block cursor, or the visual selection's end.
  readonly property alias blockPosition: internal.block
  readonly property alias searching: internal.searching
  readonly property alias searchPattern: internal.searchPattern
  readonly property alias searchFound: internal.searchFound
  signal submitRequested()
  signal copyRequested(string text)
  parent: target
  anchors.fill: parent
  z: 1

  function handleKeyEvent(event) {
    if (!active || target.inputMethodComposing) return false;
    const input = {
      text: event.text, key: keyName(event.key),
      ctrl: !!(event.modifiers & Qt.ControlModifier), meta: !!(event.modifiers & Qt.MetaModifier),
      shift: !!(event.modifiers & Qt.ShiftModifier)
    };
    const result = Core.handleKey(internal.state, {text: target.text, cursor: target.cursorPosition}, input, internal.view);
    if (!result.handled) return false;
    event.accepted = true;
    apply(result, event.isAutoRepeat);
    return true;
  }
  // Back to insert mode with a fresh history, keeping the caret or selection.
  // From normal mode the caret goes after the block, where typing stopped.
  function reset() {
    const start = target.selectionStart, end = target.selectionEnd, text = target.text;
    let position = target.cursorPosition;
    if (internal.mode === "normal" && position < text.length && text[position] !== "\n")
      position = Core.nextBoundary(text, position);
    Core.reset(internal.state, {text: target.text, cursor: position});
    internal.applying = true;
    internal.mode = "insert";
    if (end > start) target.select(start, end);
    else target.cursorPosition = position;
    internal.applying = false;
    syncSearch();
  }

  function keyName(key) {
    switch (key) {
    case Qt.Key_Escape: return "Escape";
    case Qt.Key_Return: return "Return";
    case Qt.Key_Enter: return "Enter";
    case Qt.Key_Backspace: return "Backspace";
    case Qt.Key_Delete: return "Delete";
    case Qt.Key_Left: return "Left";
    case Qt.Key_Right: return "Right";
    case Qt.Key_Up: return "Up";
    case Qt.Key_Down: return "Down";
    case Qt.Key_Home: return "Home";
    case Qt.Key_End: return "End";
    case Qt.Key_Tab: case Qt.Key_Backtab: return "Tab";
    }
    return key >= Qt.Key_A && key <= Qt.Key_Z ? String.fromCharCode(key + 32) : "";
  }
  function apply(result, repeated) {
    internal.applying = true;
    if (result.text !== undefined) {
      const change = Core.diff(target.text, result.text);
      if (change.end > change.start) target.remove(change.start, change.end);
      if (change.text) target.insert(change.start, change.text);
    }
    // The mode drives the owner's readOnly, and toggling readOnly sends Qt's
    // caret to the end of the text: switch first, then place the caret.
    internal.mode = internal.state.mode;
    if (result.selection) target.select(result.selection.start, result.selection.end);
    else { target.deselect(); target.cursorPosition = result.cursor; }
    internal.applying = false;
    internal.block = result.cursor;
    updateBlock();
    syncSearch();
    if (result.copy !== undefined) copyRequested(result.copy);
    if (result.submit && !repeated) submitRequested();
  }
  // Moves over displayed lines, keeping the horizontal position in pixels.
  function vertical(position, lines, goalX) {
    let rect = target.positionToRectangle(position);
    const x = goalX >= 0 ? goalX : rect.x;
    let result = position;
    for (let n = 0; n < Math.abs(lines); ++n) {
      const next = target.positionAt(x, lines > 0 ? rect.y + rect.height + 1 : rect.y - 1);
      const nextRect = target.positionToRectangle(next);
      if (nextRect.y === rect.y) break;
      result = next; rect = nextRect;
    }
    return {position: result, goalX: x};
  }
  // Width of the character at position on its displayed line.
  function characterWidth(position, next) {
    const rect = target.positionToRectangle(position);
    if (next > position && target.text[position] !== "\n") {
      const after = target.positionToRectangle(next);
      if (after.y === rect.y && after.x > rect.x) return after.x - rect.x;
    }
    return metrics.averageCharacterWidth;
  }
  function updateBlock() {
    if (internal.mode === "insert") return;
    const text = target.text;
    const position = Math.min(internal.block, text.length);
    const next = Core.nextBoundary(text, position);
    const rect = target.positionToRectangle(position);
    internal.blockRect = Qt.rect(rect.x, rect.y, characterWidth(position, next), rect.height);
    internal.blockText = next > position && text[position] !== "\n" ? text.slice(position, next) : "";
    blink.restartBlink();
  }
  // One box per displayed line covered by [start, end).
  function rangeBoxes(start, end) {
    const text = target.text, boxes = [];
    let box = null;
    for (let at = start; at < end;) {
      const next = Math.min(end, Core.nextBoundary(text, at));
      const rect = target.positionToRectangle(at);
      const width = characterWidth(at, next);
      if (box && box.y === rect.y && Math.abs(box.x + box.width - rect.x) < 0.5) box.width += width;
      else { box = {x: rect.x, y: rect.y, width: width, height: rect.height}; boxes.push(box); }
      at = next;
    }
    return boxes;
  }
  // Mirrors the pattern being typed and highlights its matches; the match
  // Enter would reach gets the current-match color.
  function syncSearch() {
    const search = internal.state.search;
    internal.searching = !!search;
    internal.searchPattern = search ? search.pattern : "";
    const text = target.text, pattern = internal.searchPattern;
    const matches = pattern ? Core.searchMatches(text, pattern) : [];
    const current = matches.length ? Core.nextMatch(text, pattern, Core.clampNormal(text, target.cursorPosition), true) : -1;
    const boxes = [];
    for (const match of matches)
      for (const box of rangeBoxes(match.start, match.end)) { box.current = match.start === current; boxes.push(box); }
    internal.searchFound = !pattern || matches.length > 0;
    internal.highlights = boxes;
  }
  function outsideEdit() {
    if (internal.mode === "insert") return;
    Core.forget(internal.state);
    internal.mode = internal.state.mode;
    internal.block = Core.clampNormal(target.text, target.cursorPosition);
    syncSearch();
  }
  function relayout() { updateBlock(); if (internal.searching) syncSearch(); }

  onActiveChanged: reset()
  onMultilineChanged: internal.state.multiline = multiline

  QtObject {
    id: internal
    property var state: Core.create({multiline: root.multiline})
    property string mode: "insert"
    property int block: 0
    property bool applying: false
    property rect blockRect: Qt.rect(0, 0, 0, 0)
    property string blockText: ""
    property bool searching: false
    property string searchPattern: ""
    property bool searchFound: true
    property var highlights: []
    readonly property var view: ({vertical: (position, lines, goalX) => root.vertical(position, lines, goalX)})
  }
  Connections {
    target: root.target
    function onTextChanged() { if (!internal.applying) root.outsideEdit(); root.relayout(); }
    // Mouse clicks move the block in normal mode.
    function onCursorPositionChanged() {
      if (internal.applying || internal.mode !== "normal") return;
      internal.block = Core.clampNormal(root.target.text, root.target.cursorPosition);
      root.updateBlock();
    }
    // Entering the field starts in insert mode; returning to the window does not.
    function onActiveFocusChanged() {
      if (root.target.activeFocus && root.target.focusReason !== Qt.ActiveWindowFocusReason) root.reset();
    }
    function onWidthChanged() { root.relayout(); }
    function onFontChanged() { root.relayout(); }
  }
  FontMetrics { id: metrics; font: root.target.font }
  Repeater {
    model: internal.highlights
    Rectangle {
      objectName: modelData.current ? "vimCurrentMatch" : "vimMatch"
      required property var modelData
      x: modelData.x; y: modelData.y; width: modelData.width; height: modelData.height
      color: modelData.current ? root.currentMatchColor : root.matchColor
    }
  }
  Rectangle {
    id: block
    objectName: "vimBlockCursor"
    readonly property bool shown: root.active && root.target.activeFocus && internal.mode !== "insert" && !internal.searching
    visible: shown
    opacity: blink.on ? 1 : 0
    x: internal.blockRect.x; y: internal.blockRect.y
    width: internal.blockRect.width; height: internal.blockRect.height
    color: root.cursorColor
    Text {
      objectName: "vimBlockText"
      text: internal.blockText
      textFormat: Text.PlainText
      font: root.target.font
      renderType: root.target.renderType
      color: root.cursorTextColor
    }
  }
  // Blinks at the platform caret rate, like Zed and the insert caret, and
  // shows solid again whenever the block moves.
  Timer {
    id: blink
    property bool on: true
    function restartBlink() { on = true; if (running) restart(); }
    interval: Math.max(1, Qt.styleHints.cursorFlashTime / 2); repeat: true
    running: block.shown && Qt.styleHints.cursorFlashTime > 0
    onTriggered: on = !on
    onRunningChanged: on = true
  }
}
