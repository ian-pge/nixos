import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Rectangle {
  id: root
  objectName: "beeperSidebar"
  required property var chats
  required property var currentNetwork
  property var accountConnectionIssues: ({})
  property string serviceConnectionIssue: ""
  readonly property string connectionIssue: Format.networkConnectionIssue(currentNetwork.key, accountConnectionIssues, serviceConnectionIssue)
  readonly property color networkAccent: connectionIssue ? Theme.error : Theme.beeperNetworkColors[currentNetwork.key] || Theme.secondary
  property string currentChatID: ""
  property bool showArchived: false
  property bool unreadFirst: false
  property int unreadCount: 0
  property bool unreadReady: true
  property bool unreadLoading: false
  property bool searchOpen: false
  property alias searchInput: searchField
  property alias list: chatList
  property string visibleSelectionToFollow: ""
  property int selectionFollowRevision: 0
  readonly property bool browsing: chatWheel.driving || chatList.moving || chatScrollBar.pressed
  signal networkCycleRequested()
  signal searchAccepted()
  signal chatSelected(int index)
  signal viewportChanged()
  function revealChat(index) {
    chatWheel.reset(); chatList.cancelFlick();
    chatList.forceLayout();
    chatList.positionViewAtIndex(index, ListView.Contain);
  }
  function revealFirstChat() {
    ++selectionFollowRevision;
    chatWheel.reset(); chatList.cancelFlick();
    chatList.forceLayout(); chatList.positionViewAtBeginning();
  }
  function captureVisibleSelection() {
    visibleSelectionToFollow = "";
    if (!enabled || browsing || !currentChatID) return;
    const nextIndex = chats.findIndex(chat => chat.id === currentChatID);
    if (nextIndex < 0) return;
    for (let index = 0; index < chatModel.count; ++index) {
      if (chatModel.get(index).row.id !== currentChatID) continue;
      const item = chatList.itemAtIndex(index);
      if (index !== nextIndex && item && item.y + item.height > chatList.contentY
          && item.y < chatList.contentY + chatList.height) visibleSelectionToFollow = currentChatID;
      break;
    }
  }
  function restoreVisibleSelection() {
    const id = visibleSelectionToFollow;
    const revision = selectionFollowRevision;
    visibleSelectionToFollow = "";
    if (!id) return;
    Qt.callLater(() => {
      if (!root.enabled || root.browsing || root.currentChatID !== id || root.selectionFollowRevision !== revision) return;
      const index = root.chats.findIndex(chat => chat.id === id);
      if (index >= 0) root.revealChat(index);
    });
  }
  onEnabledChanged: if (!enabled) { chatWheel.reset(); chatList.cancelFlick(); }
  color: Theme.surface; radius: 18
  ColumnLayout {
    anchors { fill: parent; margins: 16 }
    spacing: 12
    RowLayout {
      Layout.fillWidth: true
      spacing: 10
      BeeperButton {
        id: networkSelector
        objectName: "beeperNetworkFilter"
        Layout.alignment: Qt.AlignVCenter
        Layout.minimumWidth: 54; Layout.maximumWidth: 54; Layout.preferredHeight: 54
        text: root.currentNetwork.glyph
        font.pixelSize: 30
        prominent: true
        accent: root.networkAccent
        Accessible.name: root.currentNetwork.name + " conversations. Tab to switch network."
          + (root.showArchived ? " Archived conversations only." : "")
          + (root.connectionIssue ? " Connection problem: " + root.connectionIssue : "")
        ToolTip {
          visible: networkSelector.hovered
          text: root.currentNetwork.name + " · Tab / Shift+Tab" + (root.showArchived ? "\nArchives only · a to return to inbox" : "") + (root.connectionIssue ? "\n" + root.connectionIssue : "")
          palette.toolTipText: Theme.foreground
          background: Rectangle { radius: 8; color: Theme.surfaceRaised }
        }
        background: Rectangle {
          radius: width / 2
          color: Qt.alpha(networkSelector.accent, networkSelector.hovered || networkSelector.activeFocus ? 0.24 : 0.14)
        }
        Rectangle {
          objectName: "beeperNetworkConnectionWarning"
          visible: !!root.connectionIssue
          width: 18; height: 18; radius: width / 2
          x: parent.width - width + 1; y: -1; z: 2
          color: Theme.error; antialiasing: true
          Text {
            anchors.centerIn: parent; text: "!"; color: Theme.background
            font { family: "Ubuntu Nerd Font"; pixelSize: 15; bold: true }
          }
        }
        Rectangle {
          objectName: "beeperArchiveViewIndicator"
          visible: root.showArchived
          width: 20; height: 20; radius: width / 2
          x: parent.width - width + 1; y: parent.height - height + 1; z: 2
          color: root.networkAccent
          Text { anchors.centerIn: parent; text: "\uf187"; color: Theme.background; font { family: "Ubuntu Nerd Font"; pixelSize: 12 } }
          Accessible.name: "Archived conversations only"
        }
        onClicked: root.networkCycleRequested()
      }
      TextField {
        id: searchField; objectName: "beeperSearch"
        visible: root.searchOpen
        Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignVCenter
        implicitWidth: 0; implicitHeight: 46
        placeholderText: "Search conversations…"
        color: Theme.foreground; placeholderTextColor: Theme.inactive
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
        leftPadding: 12; selectByMouse: true
        background: Rectangle { radius: 10; color: Qt.alpha(Theme.surfaceRaised, searchField.activeFocus ? 0.7 : 0.45) }
        onAccepted: root.searchAccepted()
      }
      Item { visible: !root.searchOpen; Layout.fillWidth: true }
      Text {
        objectName: "beeperUnreadConversationCount"
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        text: (root.unreadFirst ? "↑ " : "") + (root.unreadReady ? root.unreadCount : root.unreadLoading ? "…" : "—") + " unread"
        textFormat: Text.PlainText
        color: root.unreadFirst || (root.unreadReady && root.unreadCount > 0) ? Theme.beeperUnread : Theme.secondary
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control; weight: Font.DemiBold }
        Accessible.name: (root.unreadReady ? (root.showArchived ? "Unread archived conversations in " : "Unread conversations in ") + root.currentNetwork.name + ": " + root.unreadCount : "Unread conversation count unavailable")
          + (root.unreadFirst ? ". Unread conversations first." : "")
        HoverHandler { id: unreadCountHover }
        ToolTip {
          visible: unreadCountHover.hovered
          text: (root.unreadReady ? (root.showArchived ? "Unread archived conversations in " : "Unread conversations in ") + root.currentNetwork.name + ", including manually marked unread"
            : root.unreadLoading ? "Counting unread conversations…" : "Unread conversation count unavailable")
            + (root.unreadFirst ? "\nUnread first · u to restore normal order" : "\nu to show unread first")
          palette.toolTipText: Theme.foreground
          background: Rectangle { radius: 8; color: Theme.surfaceRaised }
        }
      }
    }
    ListView {
      id: chatList; objectName: "beeperChats"
      Layout.fillWidth: true; Layout.fillHeight: true
      clip: true; spacing: 5
      model: KeyedListModel {
        id: chatModel
        rows: root.chats
        onUpdating: root.captureVisibleSelection()
        onUpdated: root.restoreVisibleSelection()
      }
      // Selection is keyed by chat ID below. Native current-item tracking
      // would scroll back to it when a background refresh reorders chats.
      currentIndex: -1
      highlightFollowsCurrentItem: false
      keyNavigationEnabled: false
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      acceptedButtons: Qt.NoButton
      AcceleratedScroll { id: chatWheel; flickable: chatList }
      onContentYChanged: root.viewportChanged()
      onContentHeightChanged: root.viewportChanged()
      onHeightChanged: root.viewportChanged()
      ScrollBar.vertical: ScrollBar { id: chatScrollBar; policy: ScrollBar.AsNeeded }
      delegate: Rectangle {
        id: chatRow
        objectName: "beeperChatRow-" + row.id
        required property var row
        required property int index
        width: chatList.width; height: 78; radius: 14
        readonly property bool chosen: row.id === root.currentChatID
        readonly property bool unread: Format.isChatUnread(row)
        readonly property string connectionIssue: Format.chatConnectionIssue(row, root.accountConnectionIssues, root.serviceConnectionIssue)
        readonly property color platformAccent: connectionIssue ? Theme.error : Theme.beeperNetworkColors[Format.networkBadge(row.network).key] || Theme.secondary
        color: chosen ? platformAccent : chatHover.hovered ? Qt.alpha(Theme.foreground, 0.04) : "transparent"
        HoverHandler { id: chatHover }
        MouseArea { anchors.fill: parent; onClicked: root.chatSelected(chatRow.index) }
        RowLayout {
          anchors { fill: parent; margins: 10 } spacing: 10
          BeeperAvatar {
            objectName: "beeperChatAvatar-" + chatRow.row.id
            Layout.preferredWidth: diameter; Layout.preferredHeight: diameter
            chat: chatRow.row
            connectionProblem: !!chatRow.connectionIssue
            accentBackground: chatRow.chosen
          }
          ColumnLayout {
            Layout.fillWidth: true; spacing: 5
            RowLayout {
              Layout.fillWidth: true; spacing: 4
              Text { Layout.fillWidth: true; text: Format.chatTitle(chatRow.row); elide: Text.ElideRight; color: chatRow.chosen ? Theme.background : Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control; weight: chatRow.unread ? Font.DemiBold : Font.Medium } }
              Text { text: chatRow.row.isMuted ? "󰂛" : chatRow.row.isPinned ? "󰐃" : ""; color: chatRow.chosen ? Theme.background : Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
              Text {
                objectName: "beeperChatArchiveIcon-" + chatRow.row.id
                visible: chatRow.row.isArchived === true
                text: "\uf187"; color: chatRow.chosen ? Theme.background : Theme.inactive
                font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
                Accessible.name: "Archived conversation. Shift+A to restore."
              }
            }
            Text { Layout.fillWidth: true; text: Format.preview(chatRow.row).replace(/\n/g, " "); elide: Text.ElideRight; color: chatRow.chosen ? Theme.background : Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
          }
          Rectangle {
            objectName: "beeperUnreadBadge-" + chatRow.row.id
            readonly property int diameter: 26
            visible: chatRow.unread
            Layout.minimumWidth: diameter; Layout.maximumWidth: diameter
            Layout.minimumHeight: diameter; Layout.maximumHeight: diameter
            radius: width / 2; color: Theme.beeperUnread
            Text { anchors.centerIn: parent; visible: chatRow.row.unreadCount > 0; text: chatRow.row.unreadCount > 99 ? "99" : chatRow.row.unreadCount || 0; color: Theme.background; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption; bold: true } }
          }
        }
      }
    }
  }
}
