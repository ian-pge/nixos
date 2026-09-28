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
  property bool showLowPriority: false
  property bool unreadFirst: false
  property int unreadCount: 0
  property bool unreadReady: true
  property bool unreadLoading: false
  property bool searchOpen: false
  property alias searchInput: searchField
  property alias list: chatList
  property string visibleSelectionToFollow: ""
  property int selectionFollowRevision: 0
  readonly property bool compact: width < 280
  readonly property int selectionDuration: 200
  readonly property int selectionColorDuration: 120
  readonly property bool animateSelection: enabled && visible
  readonly property int selectedRowHeight: compact ? 112 : 128
  property string revealTarget: ""
  property Item revealItem: null
  readonly property bool browsing: chatWheel.driving || chatList.moving || chatScrollBar.pressed
  signal networkCycleRequested()
  signal searchAccepted()
  signal chatSelected(int index)
  signal viewportChanged()
  function revealChat(index) {
    chatWheel.reset(); chatList.cancelFlick();
    chatList.forceLayout();
    chatList.positionViewAtIndex(index, ListView.Contain);
    revealTarget = chats[index]?.id || "";
    revealItem = chatList.itemAtIndex(index);
    selectionRevealTimeout.restart();
  }
  function containGrowingSelection() {
    const item = revealItem;
    if (!enabled || browsing || !item || !revealTarget || revealTarget !== currentChatID
        || item.row.id !== revealTarget) return;
    // ListView already lays out the changing row. Only correct a clipped edge;
    // never force another layout or scan all chats on every animation frame.
    const nextY = Math.max(chatList.originY, Math.min(item.y,
      Math.max(chatList.contentY, item.y + item.height - chatList.height)));
    if (Math.abs(nextY - chatList.contentY) > 0.5) chatList.contentY = nextY;
  }
  function stopSelectionReveal() {
    revealTarget = "";
    revealItem = null;
    selectionRevealTimeout.stop();
  }
  function revealFirstChat() {
    ++selectionFollowRevision;
    stopSelectionReveal();
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
  onEnabledChanged: if (!enabled) { stopSelectionReveal(); chatWheel.reset(); chatList.cancelFlick(); }
  Timer {
    id: selectionRevealTimeout
    interval: root.selectionDuration + 32
    onTriggered: { root.revealTarget = ""; root.revealItem = null; }
  }
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
          + (root.showLowPriority ? " Low priority conversations only." : "")
          + (root.connectionIssue ? " Connection problem: " + root.connectionIssue : "")
        ToolTip {
          visible: networkSelector.hovered
          text: root.currentNetwork.name + " · Tab / Shift+Tab" + (root.showLowPriority ? "\nLow Priority · a to return to inbox" : "") + (root.connectionIssue ? "\n" + root.connectionIssue : "")
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
          objectName: "beeperLowPriorityViewIndicator"
          visible: root.showLowPriority
          width: 20; height: 20; radius: width / 2
          x: parent.width - width + 1; y: parent.height - height + 1; z: 2
          color: root.networkAccent
          Text { anchors.centerIn: parent; text: "\uf103"; color: Theme.background; font { family: "Ubuntu Nerd Font"; pixelSize: 12 } }
          Accessible.name: "Low priority conversations only"
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
        Accessible.name: (root.unreadReady ? (root.showLowPriority ? "Unread low priority conversations in " : "Unread conversations in ") + root.currentNetwork.name + ": " + root.unreadCount : "Unread conversation count unavailable")
          + (root.unreadFirst ? ". Unread conversations first." : "")
        HoverHandler { id: unreadCountHover }
        ToolTip {
          visible: unreadCountHover.hovered
          text: (root.unreadReady ? (root.showLowPriority ? "Unread low priority conversations in " : "Unread conversations in ") + root.currentNetwork.name + ", including manually marked unread"
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
      AcceleratedScroll { id: chatWheel; flickable: chatList; onScrolled: root.stopSelectionReveal() }
      onMovementStarted: root.stopSelectionReveal()
      onContentYChanged: root.viewportChanged()
      onContentHeightChanged: root.viewportChanged()
      onHeightChanged: root.viewportChanged()
      ScrollBar.vertical: ScrollBar { id: chatScrollBar; policy: ScrollBar.AsNeeded; onPressedChanged: if (pressed) root.stopSelectionReveal() }
      delegate: Rectangle {
        id: chatRow
        objectName: "beeperChatRow-" + row.id
        required property var row
        required property int index
        width: chatList.width
        height: 78 + (root.selectedRowHeight - 78) * selectionProgress
        radius: 14
        readonly property bool chosen: row.id === root.currentChatID
        property real selectionProgress: chosen ? 1 : 0
        readonly property real avatarDiameter: root.compact ? 60 : 72
        readonly property real maximumTitleScale: root.compact ? 1.125 : 1.25
        readonly property real textX: 68 + (avatarDiameter - 48) * selectionProgress
        readonly property real expandedTextX: 20 + avatarDiameter
        readonly property real rightInset: 10 + (unread ? 36 : 0)
        readonly property real textHeight: title.implicitHeight * title.scale + 5 + metadata.height
        property color titleColor: chosen ? Theme.background : Theme.foreground
        property color subtitleColor: chosen ? Theme.background : Theme.secondary
        readonly property bool unread: Format.isChatUnread(row)
        readonly property string connectionIssue: Format.chatConnectionIssue(row, root.accountConnectionIssues, root.serviceConnectionIssue)
        readonly property color platformAccent: connectionIssue ? Theme.error : Theme.beeperNetworkColors[Format.networkBadge(row.network).key] || Theme.secondary
        color: chosen ? platformAccent : chatHover.hovered ? Qt.alpha(Theme.foreground, 0.04) : "transparent"
        Behavior on selectionProgress {
          enabled: root.animateSelection
          NumberAnimation { duration: root.selectionDuration; easing.type: Easing.OutCubic }
        }
        Behavior on color { enabled: root.animateSelection; ColorAnimation { duration: root.selectionColorDuration } }
        Behavior on titleColor { enabled: root.animateSelection; ColorAnimation { duration: root.selectionColorDuration } }
        Behavior on subtitleColor { enabled: root.animateSelection; ColorAnimation { duration: root.selectionColorDuration } }
        // Keep an explicitly chosen row visible while its size changes. Wheel
        // and scrollbar input cancel this so browsing stays under user control.
        onHeightChanged: if (chosen) Qt.callLater(root.containGrowingSelection)
        onYChanged: if (chosen) Qt.callLater(root.containGrowingSelection)
        HoverHandler { id: chatHover }
        MouseArea { anchors.fill: parent; onClicked: root.chatSelected(chatRow.index) }
        // Geometry inside the row is fixed at its largest presentation. Grow
        // the avatar/title with transforms, keeping fonts, clipping and text
        // wrapping unchanged throughout the animation.
        BeeperAvatar {
          objectName: "beeperChatAvatar-" + chatRow.row.id
          anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
          diameter: chatRow.avatarDiameter
          sourceDiameter: diameter
          transformOrigin: Item.Left
          scale: (48 + (diameter - 48) * chatRow.selectionProgress) / diameter
          chat: chatRow.row
          connectionProblem: !!chatRow.connectionIssue
          accentBackground: chatRow.chosen
        }
        Text {
          id: title
          objectName: "beeperChatTitle-" + chatRow.row.id
          x: chatRow.textX
          y: (chatRow.height - chatRow.textHeight) / 2
          width: Math.max(0, (chatRow.width - chatRow.expandedTextX - chatRow.rightInset
            - (markers.width > 0 ? markers.width + 4 : 0)) / chatRow.maximumTitleScale)
          scale: 1 + (chatRow.maximumTitleScale - 1) * chatRow.selectionProgress
          transformOrigin: Item.TopLeft
          text: Format.chatTitle(chatRow.row); textFormat: Text.PlainText
          wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
          color: chatRow.titleColor
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control; weight: chatRow.chosen || chatRow.unread ? Font.DemiBold : Font.Medium }
        }
        Row {
          id: markers
          anchors { right: parent.right; rightMargin: chatRow.rightInset }
          y: title.y + (title.implicitHeight * title.scale - height) / 2
          spacing: 4
          Text {
            text: chatRow.row.isMuted ? "󰂛" : chatRow.row.isPinned ? "󰐃" : ""
            color: chatRow.titleColor
            font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
          }
          Text {
            objectName: "beeperChatPriorityIcon-" + chatRow.row.id
            visible: chatRow.row.isLowPriority === true
            text: "\uf103"; color: chatRow.titleColor
            font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
            Accessible.name: "Low priority conversation. Shift+A to move to inbox."
          }
        }
        Item {
          id: metadata
          x: chatRow.textX
          y: title.y + title.implicitHeight * title.scale + 5
          width: Math.max(0, chatRow.width - chatRow.expandedTextX - chatRow.rightInset)
          height: Math.max(preview.implicitHeight, details.implicitHeight)
          Text {
            id: preview
            objectName: "beeperChatPreview-" + chatRow.row.id
            anchors { left: parent.left; right: parent.right }
            text: Format.preview(chatRow.row).replace(/\n/g, " "); textFormat: Text.PlainText
            elide: Text.ElideRight; color: chatRow.subtitleColor
            opacity: 1 - chatRow.selectionProgress; visible: opacity > 0
            font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
          }
          Text {
            id: details
            objectName: "beeperChatDetails-" + chatRow.row.id
            anchors { left: parent.left; right: parent.right }
            text: Format.chatSubtitle(chatRow.row) || "Direct message"; textFormat: Text.PlainText
            elide: Text.ElideRight; color: chatRow.subtitleColor
            opacity: chatRow.selectionProgress; visible: opacity > 0
            font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
          }
        }
        Rectangle {
          objectName: "beeperUnreadBadge-" + chatRow.row.id
          readonly property int diameter: 26
          anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
          visible: chatRow.unread
          width: diameter; height: diameter
          radius: width / 2; color: Theme.beeperUnread
          Text { anchors.centerIn: parent; visible: chatRow.row.unreadCount > 0; text: chatRow.row.unreadCount > 99 ? "99" : chatRow.row.unreadCount || 0; color: Theme.background; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption; bold: true } }
        }
      }
    }
  }
}
