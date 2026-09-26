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
  onMatchesChanged: {
    emojiGrid.currentIndex = matches.length ? 0 : -1;
    emojiGrid.positionViewAtBeginning();
  }
  onOpened: { searchField.text = ""; catalogLoaded = true; searchField.forceActiveFocus(); }
  contentItem: FocusScope {
    Keys.onEscapePressed: event => { root.cancelRequested(); event.accepted = true; }
    ColumnLayout {
      anchors.fill: parent; spacing: 8
      TextField {
        id: searchField
        objectName: "beeperEmojiSearch"
        Layout.fillWidth: true; implicitHeight: 40
        placeholderText: "Search emoji…"
        color: Theme.foreground; placeholderTextColor: Theme.secondary
        selectionColor: Qt.alpha(root.accent, 0.4); selectedTextColor: Theme.foreground
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
        leftPadding: 10; rightPadding: 10; selectByMouse: true
        background: Rectangle { radius: 10; color: Theme.surface }
        Keys.onPressed: event => {
          if (inputMethodComposing) return;
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!event.isAutoRepeat) root.choose(emojiGrid.currentIndex);
            event.accepted = true;
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            emojiGrid.forceActiveFocus(); event.accepted = true;
          }
        }
      }
      GridView {
        id: emojiGrid
        objectName: "beeperEmojiGrid"
        Layout.fillWidth: true; Layout.fillHeight: true
        cellWidth: width / Math.max(1, Math.floor(width / 42)); cellHeight: 42
        clip: true; reuseItems: true
        model: root.matches
        keyNavigationEnabled: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        acceptedButtons: Qt.NoButton
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        AcceleratedScroll { flickable: emojiGrid; inputEnabled: root.visible }
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (!event.isAutoRepeat) root.choose(currentIndex);
            event.accepted = true;
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            searchField.forceActiveFocus(); event.accepted = true;
          }
        }
        delegate: Button {
          id: emojiButton
          required property var modelData
          required property int index
          objectName: "beeperEmojiCell-" + index
          width: emojiGrid.cellWidth; height: emojiGrid.cellHeight
          focusPolicy: Qt.NoFocus
          Accessible.name: modelData.name
          onClicked: root.choose(index)
          background: Rectangle {
            radius: 9
            color: emojiButton.down ? Qt.alpha(root.accent, 0.3)
              : emojiButton.hovered || emojiGrid.activeFocus && emojiButton.GridView.isCurrentItem ? Qt.alpha(root.accent, 0.18) : "transparent"
          }
          contentItem: Text {
            text: emojiButton.modelData.emoji; textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            color: Theme.foreground
            font { family: "Noto Color Emoji"; pixelSize: 26 }
          }
          ToolTip {
            visible: emojiButton.hovered; delay: 500; text: emojiButton.modelData.name
            palette.toolTipText: Theme.foreground
            background: Rectangle { radius: 8; color: Theme.surface }
          }
        }
        Text {
          anchors.centerIn: parent; visible: emojiGrid.count === 0
          text: "No emoji found"; color: Theme.secondary
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
        }
      }
    }
  }
}
