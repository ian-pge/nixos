import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperEmojiData.js" as EmojiData

Popup {
  id: root
  objectName: "beeperEmojiPicker"
  property color accent: Theme.secondary
  property alias searchInput: searchField
  property alias grid: emojiGrid
  property bool catalogLoaded: false
  property Item hoveredEmoji: null
  readonly property var matches: catalogLoaded ? EmojiData.search(searchField.text) : []
  signal emojiSelected(string emoji)
  signal cancelRequested()
  width: Math.min(360, parent ? parent.width : 360)
  height: 360
  padding: 12; margins: 12
  focus: true; modal: false
  popupType: Popup.Item
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  background: Rectangle { radius: 16; color: Theme.surfaceRaised }
  function choose(index) {
    const entry = matches[index];
    if (visible && entry) emojiSelected(entry.emoji);
  }
  function search() { searchField.forceActiveFocus(); searchField.selectAll(); }
  onMatchesChanged: {
    hoveredEmoji = null;
    emojiGrid.currentIndex = matches.length ? 0 : -1;
    emojiGrid.positionViewAtBeginning();
  }
  onOpened: { searchField.text = ""; catalogLoaded = true; emojiGrid.forceActiveFocus(); }
  ToolTip {
    parent: root.hoveredEmoji || root.contentItem
    visible: root.visible && root.hoveredEmoji !== null
    delay: 500; text: root.hoveredEmoji?.entry.name || ""
    palette.toolTipText: Theme.foreground
    background: Rectangle { radius: 8; color: Theme.surface }
  }
  contentItem: FocusScope {
    Keys.onEscapePressed: event => { root.cancelRequested(); event.accepted = true; }
    ColumnLayout {
      anchors.fill: parent; spacing: 8
      TextField {
        id: searchField
        objectName: "beeperEmojiSearch"
        Layout.fillWidth: true; implicitHeight: 40
        placeholderText: "Search emoji…  /"
        color: Theme.foreground; placeholderTextColor: Theme.secondary
        selectionColor: Qt.alpha(root.accent, 0.4); selectedTextColor: Theme.foreground
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
        leftPadding: 10; rightPadding: 10; selectByMouse: true
        background: Rectangle { radius: 10; color: Theme.surface }
        Keys.onPressed: event => {
          if (inputMethodComposing) return;
          // Enter hands the results to the keyboard, on the first match,
          // so the right emoji can be picked; it never inserts from here.
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat && root.matches.length) emojiGrid.forceActiveFocus();
            event.accepted = true;
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            emojiGrid.forceActiveFocus(); event.accepted = true;
          }
        }
      }
      Flickable {
        id: emojiGrid
        objectName: "beeperEmojiGrid"
        Layout.fillWidth: true; Layout.fillHeight: true
        readonly property int columns: Math.max(1, Math.floor(width / 42))
        readonly property real cellWidth: width / columns
        readonly property real cellHeight: 42
        readonly property int count: root.matches.length
        property int currentIndex: -1
        readonly property int firstIndex: Math.max(0, Math.floor(contentY / cellHeight) - 1) * columns
        readonly property Item currentItem: itemAtIndex(currentIndex)
        // A fixed pool covers the popup plus two rows. Search and scrolling
        // only change each cell's entry, never thousands of model objects.
        contentHeight: Math.ceil(count / columns) * cellHeight
        contentWidth: width
        clip: true
        function itemAtIndex(index) { return index >= firstIndex && index < count ? emojiCells.itemAt(index - firstIndex) : null; }
        function positionViewAtBeginning() { emojiWheel.reset(); cancelFlick(); contentY = 0; }
        function positionViewAtIndex(index, mode) {
          if (index < 0 || index >= count) return;
          emojiWheel.reset(); cancelFlick();
          const top = Math.floor(index / columns) * cellHeight;
          let target = contentY;
          if (mode === GridView.Beginning || top < contentY) target = top;
          else if (top + cellHeight > contentY + height) target = top + cellHeight - height;
          contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), target));
        }
        function moveSelection(delta) {
          if (!count) return;
          if (Math.abs(delta) === columns && (currentIndex + delta < 0 || currentIndex + delta >= count)) return;
          currentIndex = Math.max(0, Math.min(count - 1, currentIndex + delta));
          positionViewAtIndex(currentIndex, GridView.Contain);
        }
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        acceptedButtons: Qt.NoButton
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        AcceleratedScroll { id: emojiWheel; flickable: emojiGrid; inputEnabled: root.visible }
        Keys.onPressed: event => {
          if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (!event.isAutoRepeat) root.choose(currentIndex);
            event.accepted = true;
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.search(); event.accepted = true;
          } else if (event.key === Qt.Key_Slash || event.text === "/") {
            root.search(); event.accepted = true;
          } else if ([Qt.Key_H, Qt.Key_J, Qt.Key_K, Qt.Key_L, Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(event.key)) {
            if (event.key === Qt.Key_H || event.key === Qt.Key_Left) moveSelection(-1);
            else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) moveSelection(columns);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) moveSelection(-columns);
            else moveSelection(1);
            event.accepted = true;
          }
        }
        Repeater {
          id: emojiCells
          model: emojiGrid.columns * (Math.ceil(root.height / emojiGrid.cellHeight) + 2)
          delegate: Rectangle {
            id: emojiButton
            required property int index
            readonly property int entryIndex: emojiGrid.firstIndex + index
            readonly property var entry: root.matches[entryIndex] || {emoji: "", name: ""}
            objectName: "beeperEmojiCell-" + entryIndex
            x: entryIndex % emojiGrid.columns * emojiGrid.cellWidth
            y: Math.floor(entryIndex / emojiGrid.columns) * emojiGrid.cellHeight
            width: emojiGrid.cellWidth; height: emojiGrid.cellHeight
            visible: entryIndex < emojiGrid.count
            radius: 9
            Accessible.role: Accessible.Button
            Accessible.name: entry.name
            Accessible.onPressAction: root.choose(entryIndex)
            color: emojiTap.pressed ? Qt.alpha(root.accent, 0.3)
              : emojiHover.hovered || emojiGrid.activeFocus && emojiGrid.currentIndex === entryIndex ? Qt.alpha(root.accent, 0.18) : "transparent"
            TapHandler { id: emojiTap; onTapped: root.choose(emojiButton.entryIndex) }
            HoverHandler {
              id: emojiHover
              onHoveredChanged: {
                if (hovered) root.hoveredEmoji = emojiButton;
                else if (root.hoveredEmoji === emojiButton) root.hoveredEmoji = null;
              }
            }
            Text {
              anchors.fill: parent
              text: emojiButton.y + emojiButton.height > emojiGrid.contentY - emojiGrid.cellHeight
                && emojiButton.y < emojiGrid.contentY + emojiGrid.height + emojiGrid.cellHeight ? emojiButton.entry.emoji : ""
              textFormat: Text.PlainText
              horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
              color: Theme.foreground
              font { family: "Noto Color Emoji"; pixelSize: 26 }
            }
          }
        }
        Text {
          parent: emojiGrid
          anchors.centerIn: parent; visible: emojiGrid.count === 0
          text: "No emoji found"; color: Theme.secondary
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
        }
      }
      Text {
        Layout.fillWidth: true
        text: "H J K L / arrows · Move    / · Search\nEnter / Space · Insert    Esc · Cancel"
        color: Theme.secondary
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
        wrapMode: Text.Wrap
      }
    }
  }
}
