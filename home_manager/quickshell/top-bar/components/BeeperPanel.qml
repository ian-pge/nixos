import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "Theme.js" as Theme
import "BeeperFormat.js" as Format

FocusScope {
  id: root
  required property var beeperData
  property bool active: false
  property bool windowFocused: false
  property bool dictating: false
  property real dictationEnergy: 0
  property string navigation: "chats"
  property int chatIndex: 0
  property int messageIndex: -1
  property string accountFilter: ""
  property bool showArchived: false
  property string modal: ""
  property int actionIndex: 0
  property string editMessageID: ""
  property string editText: ""
  property var previewAttachment: null
  property var recordingAttachment: null
  property string recordingChatID: ""
  property bool preparingRecording: false
  property var recorder: null
  property bool gPending: false
  property var contacts: []
  property string newAccountID: ""
  property string pendingOpenMessageID: ""
  property string displayedChatID: ""
  property int targetPageCount: 0
  property bool restoringView: false
  readonly property bool compact: width < 780
  readonly property bool recording: recorder !== null && recorder.recording
  readonly property var selectedMessage: messageIndex >= 0 && messageIndex < beeperData.messages.length ? beeperData.messages[messageIndex] : null
  readonly property var filteredChats: beeperData.chats.filter(chat => !!chat.isArchived === showArchived && (!accountFilter || chat.accountID === accountFilter) && (!searchField.text || (Format.chatTitle(chat) + " " + Format.preview(chat)).toLowerCase().includes(searchField.text.toLowerCase())))
  readonly property var actions: [
    {id: "reply", label: "Répondre au message", key: "r", enabled: !!selectedMessage && Format.supports(beeperData.currentChat, "reply")},
    {id: "react", label: "Ajouter une réaction", key: "+", enabled: !!selectedMessage && Format.supports(beeperData.currentChat, "reaction")},
    {id: "edit", label: "Modifier le message", key: "e", enabled: !!selectedMessage?.isSender && Format.supports(beeperData.currentChat, "edit", selectedMessage)},
    {id: "delete", label: "Supprimer le message", key: "", enabled: !!selectedMessage?.isSender && Format.supports(beeperData.currentChat, "delete", selectedMessage)},
    {id: "media", label: "Ouvrir le média", key: "o", enabled: !!selectedMessage?.attachments?.length},
    {id: "read", label: "Marquer comme lu", key: "", enabled: !!beeperData.currentChatID},
    {id: "pin", label: beeperData.currentChat?.isPinned ? "Désépingler la conversation" : "Épingler la conversation", key: "", enabled: !!beeperData.currentChatID},
    {id: "mute", label: beeperData.currentChat?.isMuted ? "Réactiver les notifications" : "Mettre en sourdine", key: "", enabled: !!beeperData.currentChatID},
    {id: "archive", label: beeperData.currentChat?.isArchived ? "Désarchiver la conversation" : "Archiver la conversation", key: "", enabled: !!beeperData.currentChatID && beeperData.currentChat?.capabilities?.archive !== false},
    {id: "archives", label: showArchived ? "Revenir à la boîte de réception" : "Voir les archives", key: "", enabled: true},
    {id: "attach", label: "Joindre un fichier", key: "", enabled: !!beeperData.currentChatID && !beeperData.currentChat?.isReadOnly},
    {id: "record", label: recording ? "Terminer le vocal" : "Enregistrer un vocal", key: "", enabled: !!beeperData.currentChatID && !beeperData.currentChat?.isReadOnly},
    {id: "search", label: "Rechercher dans les messages", key: "", enabled: true},
    {id: "new", label: "Nouvelle conversation", key: "", enabled: true},
    {id: "refresh", label: "Actualiser", key: "", enabled: true},
    {id: "help", label: "Aide clavier", key: "?", enabled: true}
  ].concat(Format.links(selectedMessage).map(link => ({id: "link:" + link.url, label: "Ouvrir « " + (link.title || link.url) + " »", key: "", enabled: true})))
  readonly property var filteredActions: actions.filter(action => action.enabled && (!modalInput.text || action.label.toLowerCase().includes(modalInput.text.toLowerCase())))
  signal closeRequested()
  signal nativeDialogOpened()
  signal nativeDialogClosed()
  implicitWidth: 1280
  implicitHeight: 900
  clip: true

  function focusNavigation() { if (!active) return; navigation = "chats"; navigationFocus.forceActiveFocus(); }
  function openChat(chatID, messageID) { pendingOpenMessageID = messageID || ""; beeperData.selectChat(chatID, messageID || ""); navigation = "messages"; }
  function chooseChat(index) {
    if (!filteredChats.length) return;
    chatIndex = Math.max(0, Math.min(filteredChats.length - 1, index));
    rememberPosition();
    if (recording) stopRecording();
    editMessageID = ""; beeperData.selectChat(filteredChats[chatIndex].id); messageIndex = -1;
    chatList.positionViewAtIndex(chatIndex, ListView.Contain);
  }
  function moveSelection(delta) {
    if (navigation === "chats") chooseChat(chatIndex + delta);
    else {
      messageIndex = Math.max(0, Math.min(beeperData.messages.length - 1, (messageIndex < 0 ? beeperData.messages.length - 1 : messageIndex) + delta));
      messageList.positionViewAtIndex(messageIndex, ListView.Contain);
    }
  }
  function goEdge(last) {
    if (navigation === "chats") chooseChat(last ? filteredChats.length - 1 : 0);
    else {
      messageIndex = last ? beeperData.messages.length - 1 : 0;
      messageList.positionViewAtIndex(messageIndex, ListView.Contain);
      if (!last && beeperData.hasOlderMessages) beeperData.loadMessages(true);
    }
  }
  function compose() { if (beeperData.currentChatID) { navigation = "compose"; composer.forceActiveFocus(); } }
  function openModal(name) {
    modal = name; actionIndex = 0; modalInput.text = "";
    if (name === "new") newAccountID = beeperData.accounts[0]?.id || "";
    Qt.callLater(() => name === "help" || name === "media" || name === "delete" ? modalSurface.forceActiveFocus() : modalInput.forceActiveFocus());
  }
  function closeModal() { modal = ""; navigationFocus.forceActiveFocus(); }
  function submitMessage() {
    if (recording || preparingRecording || composer.inputMethodComposing) return;
    if (editMessageID) {
      const id = editMessageID, chatID = beeperData.currentChatID, text = composer.text;
      beeperData.request("edit", {chatID: chatID, messageID: id, text: text}, (result, error) => {
        if (!error && chatID === beeperData.currentChatID) { editMessageID = ""; editText = ""; beeperData.loadMessages(false); }
      });
    } else beeperData.sendMessage();
  }
  function runAction(id) {
    const action = actions.find(item => item.id === id);
    if (action && !action.enabled) return;
    const chatID = beeperData.currentChatID, message = selectedMessage;
    closeModal();
    if (id === "reply" && message) { beeperData.replyToMessageID = message.id; compose(); }
    else if (id === "react" && message) openModal("react");
    else if (id === "edit" && message?.isSender) { editText = Format.text(message); editMessageID = message.id; compose(); }
    else if (id === "delete" && message?.isSender) openModal("delete");
    else if (id === "media" && message?.attachments?.length) { previewAttachment = message.attachments[0]; openModal("media"); }
    else if (id === "read") beeperData.request("read", {chatID: chatID});
    else if (id === "pin") beeperData.request("updateChat", {chatID: chatID, changes: {isPinned: !beeperData.currentChat?.isPinned}}, () => beeperData.refreshChats(false));
    else if (id === "mute") beeperData.request("updateChat", {chatID: chatID, changes: {isMuted: !beeperData.currentChat?.isMuted}}, () => beeperData.refreshChats(false));
    else if (id === "archive") beeperData.request("updateChat", {chatID: chatID, changes: {isArchived: !beeperData.currentChat?.isArchived}}, () => beeperData.refreshChats(false));
    else if (id === "archives") showArchived = !showArchived;
    else if (id.startsWith("link:")) Qt.openUrlExternally(id.slice(5));
    else if (id === "attach") fileDialog.open();
    else if (id === "record") recording ? stopRecording() : startRecording();
    else if (id === "refresh") beeperData.request("refresh", {}, () => beeperData.refresh());
    else if (["search", "new", "help"].includes(id)) openModal(id);
  }
  function submitModal() {
    if (modal === "actions") { if (filteredActions[actionIndex]) runAction(filteredActions[actionIndex].id); }
    else if (modal === "react" && selectedMessage && modalInput.text.trim()) {
      beeperData.request("react", {chatID: beeperData.currentChatID, messageID: selectedMessage.id, reactionKey: modalInput.text.trim()}, () => beeperData.loadMessages(false)); closeModal();
    } else if (modal === "search") {
      const query = modalInput.text;
      beeperData.request("search", {query: query}, (result, error) => { if (!error && modal === "search" && modalInput.text === query) beeperData.searchResults = result.items || []; });
    } else if (modal === "new" && modalInput.text.trim()) startChat(modalInput.text.trim());
    else if (modal === "delete" && selectedMessage) {
      const chatID = beeperData.currentChatID, messageID = selectedMessage.id;
      beeperData.request("delete", {chatID: chatID, messageID: messageID}, (result, error) => {
        if (error || chatID !== beeperData.currentChatID) return;
        beeperData.messages = beeperData.messages.filter(message => message.id !== messageID); beeperData.loadMessages(false);
      }); closeModal();
    }
  }
  function startChat(userID) {
    beeperData.request("startChat", {accountID: newAccountID, userID: userID}, (result, error) => {
      if (!error && result) { beeperData.refreshChats(false); openChat(result.chatID || result.id, ""); closeModal(); }
    });
  }
  function startRecording() {
    if (beeperData.demo) { beeperData.lastError = "L’aperçu du design n’active pas le microphone."; return; }
    if (recording || preparingRecording || !beeperData.currentChatID) return;
    preparingRecording = true; recordingChatID = beeperData.currentChatID;
    beeperData.request("prepareRecording", {}, (result, error) => {
      preparingRecording = false;
      if (error || !result) return;
      if (!active || recordingChatID !== beeperData.currentChatID) { beeperData.request("discardAttachment", {path: result.path}); return; }
      recordingAttachment = result;
      recorder = recorderComponent.createObject(root, {outputPath: result.path});
      recorder.start();
    });
  }
  function stopRecording() { if (recorder) recorder.stop(); }
  function rememberPosition() {
    if ((!active && beeperData.viewOwner !== root) || !displayedChatID || !messageList.count || restoringView) return;
    const index = Math.max(0, messageList.indexAt(1, messageList.contentY + 12)), item = messageList.itemAtIndex(index);
    beeperData.viewPositions[displayedChatID] = {atLatest: messageList.atYEnd, messageID: beeperData.messages[index]?.id || "", offset: item ? messageList.contentY - item.y : 0, contentY: messageList.contentY};
  }
  function restorePosition() {
    if (!active) return;
    restoringView = true;
    if (beeperData.loadingMessages && !beeperData.messages.length) return;
    messageList.forceLayout();
    const saved = beeperData.viewPositions[beeperData.currentChatID];
    const index = saved ? beeperData.messages.findIndex(message => message.id === saved.messageID) : -1;
    if (saved && !saved.atLatest) {
      if (index >= 0) {
        messageList.positionViewAtIndex(index, ListView.Beginning);
        const item = messageList.itemAtIndex(index);
        if (item) messageList.contentY = item.y + (saved.offset || 0);
      } else messageList.contentY = saved.contentY || messageList.originY;
    } else messageList.positionViewAtEnd();
    displayedChatID = beeperData.currentChatID;
    Qt.callLater(() => { restoringView = false; updateView(); });
  }
  function updateView() {
    if (!beeperData || !messageList) return;
    if (active) {
      beeperData.viewOwner = root;
      beeperData.viewFocused = !restoringView && windowFocused && modal !== "media";
      beeperData.viewAtLatest = !restoringView && messageList.atYEnd;
      readTimer.restart();
    } else if (beeperData.viewOwner === root) { beeperData.viewOwner = null; beeperData.viewFocused = false; }
  }
  onActiveChanged: {
    if (!active) { rememberPosition(); stopRecording(); beeperData.flushDraft(); modal = ""; }
    else { restoringView = true; Qt.callLater(restorePosition); }
    updateView();
  }
  onWindowFocusedChanged: updateView()
  onModalChanged: updateView()
  onFilteredChatsChanged: chatIndex = Math.max(0, Math.min(chatIndex, filteredChats.length - 1))
  Connections {
    target: root.beeperData
    function onTokenStored() { tokenField.text = ""; }
    function onMessagesUpdating() { if (root.active) root.rememberPosition(); }
    function onCurrentChatIDChanged() { if (root.active) { root.rememberPosition(); root.restoringView = true; } }
    function onMessagesLoaded(older) {
      if (!root.active) return;
      const wanted = root.pendingOpenMessageID || root.beeperData.targetMessageID || "";
      const index = wanted ? root.beeperData.messages.findIndex(message => message.id === wanted) : -1;
      if (index >= 0) { root.messageIndex = index; messageList.positionViewAtIndex(index, ListView.Center); root.pendingOpenMessageID = ""; root.beeperData.targetMessageID = ""; root.targetPageCount = 0; root.restoringView = false; }
      else if (wanted && root.beeperData.hasOlderMessages && root.targetPageCount < 20) { ++root.targetPageCount; Qt.callLater(() => root.beeperData.loadMessages(true)); }
      else if (wanted) { root.beeperData.lastError = "Ce message n’est pas disponible dans l’historique chargé."; root.pendingOpenMessageID = ""; root.beeperData.targetMessageID = ""; root.targetPageCount = 0; root.restoringView = false; }
      else if (older || root.displayedChatID !== root.beeperData.currentChatID) Qt.callLater(root.restorePosition);
      else if (!older && root.beeperData.followLatest) Qt.callLater(() => messageList.positionViewAtEnd());
      root.displayedChatID = root.beeperData.currentChatID;
      if (!wanted) root.restoringView = false;
      readTimer.restart();
    }
  }
  Timer {
    id: readTimer; interval: 180
    onTriggered: {
      if (!root.active || !root.windowFocused || root.restoringView || root.beeperData.viewOwner !== root || !messageList.atYEnd || root.beeperData.loadingMessages || root.modal === "media") return;
      const rows = root.beeperData.messages, chatID = root.beeperData.currentChatID;
      if (!chatID || !rows.length) return;
      const messageID = rows[rows.length - 1].id;
      if (root.beeperData.readMarkers[chatID] === messageID) return;
      root.beeperData.readMarkers[chatID] = messageID;
      root.beeperData.request("read", {chatID: chatID}, (result, error) => { if (error) delete root.beeperData.readMarkers[chatID]; });
    }
  }
  Timer { id: gTimer; interval: 650; onTriggered: root.gPending = false }
  Timer {
    id: contactTimer; interval: 250
    onTriggered: {
      const query = modalInput.text, account = root.newAccountID;
      root.beeperData.request("contacts", {accountID: account, query: query}, (result, error) => { if (!error && query === modalInput.text && root.modal === "new") root.contacts = result.items || []; });
    }
  }
  Component {
    id: recorderComponent
    BeeperRecorder {
      onFinished: path => {
        if (root.recordingChatID === root.beeperData.currentChatID) root.beeperData.draftAttachment = root.recordingAttachment;
        else root.beeperData.request("saveDraft", {chatID: root.recordingChatID, text: root.beeperData.localDrafts[root.recordingChatID]?.text || "", attachment: root.recordingAttachment});
        root.recorder = null; destroy();
      }
      onFailed: message => { root.beeperData.lastError = message; root.recorder = null; destroy(); }
    }
  }
  FileDialog {
    id: fileDialog
    title: "Joindre une pièce jointe"
    fileMode: FileDialog.OpenFile
    onVisibleChanged: visible ? root.nativeDialogOpened() : root.nativeDialogClosed()
    onAccepted: root.beeperData.stageAttachment(selectedFile.toString())
  }
  Item { id: navigationFocus; focus: true }
  Keys.onPressed: event => {
    if (!root.active) return;
    if (event.key === Qt.Key_Escape) {
      if (modal) closeModal();
      else if (composer.activeFocus || searchField.activeFocus) { navigation = "messages"; navigationFocus.forceActiveFocus(); }
      else closeRequested();
      event.accepted = true; return;
    }
    if (modal || composer.activeFocus || searchField.activeFocus || tokenField.activeFocus) return;
    const key = event.text || (event.key >= Qt.Key_A && event.key <= Qt.Key_Z ? String.fromCharCode(event.key + (event.modifiers & Qt.ShiftModifier ? 0 : 32)) : "");
    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_D || event.key === Qt.Key_U)) {
      const list = navigation === "chats" ? chatList : messageList;
      list.contentY = Math.max(list.originY, Math.min(list.originY + list.contentHeight - list.height, list.contentY + list.height * (event.key === Qt.Key_D ? 0.5 : -0.5))); event.accepted = true;
    } else if (key === "j" || key === "k") { moveSelection(key === "j" ? 1 : -1); event.accepted = true; }
    else if (key === "h" || key === "l") { navigation = key === "h" ? "chats" : "messages"; event.accepted = true; }
    else if (key === "g") { if (gPending) { goEdge(false); gPending = false; } else { gPending = true; gTimer.restart(); } event.accepted = true; }
    else if (key === "G") { goEdge(true); event.accepted = true; }
    else if (key === "/") { searchField.forceActiveFocus(); event.accepted = true; }
    else if (key === "i") { compose(); event.accepted = true; }
    else if (key === "?") { openModal("help"); event.accepted = true; }
    else if (key === ":" || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_K)) { openModal("actions"); event.accepted = true; }
    else if (key === "r" && selectedMessage) { runAction("reply"); event.accepted = true; }
    else if (key === "e" && selectedMessage?.isSender) { runAction("edit"); event.accepted = true; }
    else if (key === "o" && selectedMessage?.attachments?.length) { runAction("media"); event.accepted = true; }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { navigation === "chats" ? navigation = "messages" : openModal("actions"); event.accepted = true; }
  }

  RowLayout {
    anchors { fill: parent; margins: 20 }
    spacing: 0
    Rectangle {
      Layout.preferredWidth: root.compact ? 232 : 338
      Layout.fillHeight: true
      color: Qt.alpha(Theme.background, 0.23); radius: 18
      ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 12
        RowLayout {
          Layout.fillWidth: true
          ColumnLayout {
            spacing: 3; Layout.fillWidth: true
            Text { text: "Messages"; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.heading; weight: Font.DemiBold } }
            Row {
              spacing: 6
              Rectangle { width: 5; height: 5; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: root.beeperData.connected ? Theme.sideNotifications : Theme.inactive }
              Text { text: root.beeperData.demo ? "Aperçu du design" : root.beeperData.connected ? "Tous tes réseaux, ici" : root.beeperData.tokenRequired ? "Connexion requise" : "Reconnexion…"; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
            }
          }
          BeeperButton { text: "+"; font.pixelSize: Theme.beeperFont.icon; onClicked: root.openModal("new"); Accessible.name: "Nouvelle conversation" }
        }
        TextField {
          id: searchField; objectName: "beeperSearch"
          Layout.fillWidth: true; implicitHeight: 46
          placeholderText: "Rechercher une conversation   /"
          color: Theme.foreground; placeholderTextColor: Theme.inactive
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
          leftPadding: 12; selectByMouse: true
          background: Rectangle { radius: 10; color: Qt.alpha(Theme.surfaceRaised, 0.45); border.width: searchField.activeFocus ? 1 : 0; border.color: Qt.alpha(Theme.sideApplications, 0.5) }
      onAccepted: { root.chooseChat(0); root.navigation = "messages"; navigationFocus.forceActiveFocus(); }
        }
        BeeperAccountPicker {
          id: accountPicker
          Layout.fillWidth: true; implicitHeight: 42
          model: [{id: "", network: "Tous les comptes"}].concat(root.beeperData.accounts)
          onActivated: root.accountFilter = currentValue
        }
        ListView {
          id: chatList; objectName: "beeperChats"
          Layout.fillWidth: true; Layout.fillHeight: true
          clip: true; spacing: 5
          model: root.filteredChats
          currentIndex: root.chatIndex
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          delegate: Rectangle {
            id: chatRow
            required property var modelData
            required property int index
            width: chatList.width; height: 94; radius: 14
            readonly property bool chosen: modelData.id === root.beeperData.currentChatID
            color: chosen ? Qt.alpha(Theme.sideApplications, 0.12) : chatHover.hovered ? Qt.alpha(Theme.foreground, 0.04) : "transparent"
            border.width: chosen && root.navigation === "chats" && root.activeFocus ? 1 : 0
            border.color: Qt.alpha(Theme.sideApplications, 0.32)
            HoverHandler { id: chatHover }
            MouseArea { anchors.fill: parent; onClicked: { root.chooseChat(chatRow.index); root.navigation = "chats"; navigationFocus.forceActiveFocus(); } }
            RowLayout {
              anchors { fill: parent; margins: 10 } spacing: 10
              Rectangle {
                Layout.preferredWidth: 48; Layout.preferredHeight: 48; radius: 16
                color: Qt.alpha([Theme.sideApplications, Theme.sideSystem, Theme.sideWeather, Theme.sideDate][chatRow.index % 4], 0.14)
                Text { anchors.centerIn: parent; text: Format.initials(Format.chatTitle(chatRow.modelData)); color: [Theme.sideApplications, Theme.sideSystem, Theme.sideWeather, Theme.sideDate][chatRow.index % 4]; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label; weight: Font.Medium } }
                Image { anchors.fill: parent; source: Format.chatAvatarSource(chatRow.modelData); fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready; asynchronous: true }
              }
              ColumnLayout {
                Layout.fillWidth: true; spacing: 5
                RowLayout {
                  Layout.fillWidth: true; spacing: 4
                  Text { Layout.fillWidth: true; text: Format.chatTitle(chatRow.modelData); elide: Text.ElideRight; color: chatRow.chosen ? Theme.selectedForeground : Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control; weight: chatRow.modelData.unreadCount ? Font.DemiBold : Font.Medium } }
                  Text { text: chatRow.modelData.isMuted ? "󰂛" : chatRow.modelData.isPinned ? "󰐃" : ""; color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
                }
                Text { Layout.fillWidth: true; text: Format.preview(chatRow.modelData).replace(/\n/g, " "); elide: Text.ElideRight; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
                Text { text: chatRow.modelData.network || ""; color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
              }
              Rectangle {
                visible: chatRow.modelData.unreadCount > 0
                Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: 8; color: Qt.alpha(Theme.sideApplications, 0.2)
                Text { anchors.centerIn: parent; text: chatRow.modelData.unreadCount > 99 ? "99" : chatRow.modelData.unreadCount || 0; color: Theme.sideApplications; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption; bold: true } }
              }
            }
          }
          footer: BeeperButton { width: chatList.width; visible: root.beeperData.hasMoreChats; height: visible ? 42 : 0; text: "Plus de conversations"; onClicked: root.beeperData.refreshChats(true) }
        }
        RowLayout {
          Layout.fillWidth: true
          Text { Layout.fillWidth: true; text: root.beeperData.loading ? "Synchronisation…" : root.filteredChats.length + " conversations"; color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
          BeeperButton { text: "?"; onClicked: root.openModal("help"); Accessible.name: "Aide clavier" }
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: root.compact ? 14 : 25
      spacing: 0
      RowLayout {
        Layout.fillWidth: true; Layout.preferredHeight: 82
        ColumnLayout {
          Layout.fillWidth: true; spacing: 5
          Text { Layout.fillWidth: true; text: Format.chatTitle(root.beeperData.currentChat); elide: Text.ElideRight; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.title; weight: Font.DemiBold } }
          Text { Layout.fillWidth: true; text: root.beeperData.currentChat ? (root.beeperData.currentChat.network || "") + (root.beeperData.currentChat.isMuted ? "  ·  Notifications en sourdine" : "") : "Un espace calme pour garder le lien"; elide: Text.ElideRight; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
        }
        BeeperButton { text: "⌕"; onClicked: root.openModal("search"); Accessible.name: "Rechercher dans les messages" }
        BeeperButton { text: "•••"; onClicked: root.openModal("actions"); Accessible.name: "Actions" }
        BeeperButton { text: "×"; font.pixelSize: Theme.beeperFont.icon; onClicked: root.closeRequested(); Accessible.name: "Replier les messages" }
      }
      Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(Theme.foreground, 0.08) }
      Item {
        Layout.fillWidth: true; Layout.fillHeight: true
        ListView {
          id: messageList; objectName: "beeperMessages"
          anchors { fill: parent; topMargin: 14; bottomMargin: 12 }
          clip: true; model: root.beeperData.messages
          spacing: 4; boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          onAtYEndChanged: root.updateView()
          header: Item {
            width: messageList.width; height: root.beeperData.hasOlderMessages ? 54 : 30
            BeeperButton { anchors.centerIn: parent; visible: root.beeperData.hasOlderMessages; text: root.beeperData.loadingMessages ? "Chargement…" : "Messages précédents"; enabled: !root.beeperData.loadingMessages; onClicked: root.beeperData.loadMessages(true) }
            Text { anchors.centerIn: parent; visible: !root.beeperData.hasOlderMessages; text: root.beeperData.messages.length ? Format.dateLabel(root.beeperData.messages[0].timestamp) : ""; color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
          }
          delegate: BeeperMessage {
            required property var modelData
            required property int index
            width: messageList.width
            message: modelData; beeperData: root.beeperData
            selected: index === root.messageIndex && root.navigation === "messages"
            playbackEnabled: root.active
            onSelectedRequested: { root.messageIndex = index; root.navigation = "messages"; navigationFocus.forceActiveFocus(); }
            onActionsRequested: root.openModal("actions")
            onPreviewRequested: attachment => { root.previewAttachment = attachment; root.openModal("media"); }
          }
        }
        Column {
          visible: !root.beeperData.currentChatID || (root.beeperData.messages.length === 0 && !root.beeperData.loadingMessages)
          anchors.centerIn: parent; width: Math.min(parent.width - 40, 340); spacing: 15
          Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰍡"; color: Qt.alpha(Theme.sideApplications, 0.6); font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.illustration } }
          Text { width: parent.width; text: root.beeperData.currentChatID ? "La conversation commence ici." : "Tout le monde,\nau même endroit."; horizontalAlignment: Text.AlignHCenter; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.subheading; weight: Font.Medium } wrapMode: Text.Wrap }
          Text { width: parent.width; text: root.beeperData.currentChatID ? "Écris un premier message." : "Choisis une conversation, ou prends des nouvelles de quelqu’un."; horizontalAlignment: Text.AlignHCenter; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control } wrapMode: Text.Wrap }
        }
      }
      Rectangle {
        Layout.fillWidth: true; Layout.bottomMargin: 10
        implicitHeight: errorText.implicitHeight + 18
        visible: !!root.beeperData.lastError
        color: Qt.alpha(Theme.error, 0.09); radius: 10
        Text { id: errorText; anchors { left: parent.left; right: dismissError.left; verticalCenter: parent.verticalCenter; margins: 10 } text: root.beeperData.lastError; color: Theme.error; wrapMode: Text.Wrap; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
        BeeperButton { id: dismissError; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: "×"; onClicked: root.beeperData.lastError = "" }
      }
      Rectangle {
        id: composerSurface
        Layout.fillWidth: true
        implicitHeight: composerColumn.implicitHeight + 22
        color: Qt.alpha(Theme.surface, 0.85); radius: 17
        border.width: 1; border.color: composer.activeFocus ? Qt.alpha(Theme.sideApplications, 0.4) : Qt.alpha(Theme.foreground, 0.07)
        enabled: !!root.beeperData.currentChatID && !root.beeperData.currentChat?.isReadOnly
        ColumnLayout {
          id: composerColumn
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11 }
          spacing: 7
          RowLayout {
            visible: !!root.beeperData.replyToMessageID || !!root.editMessageID
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: root.editMessageID ? "Modifier le message" : "↪ Réponse au message sélectionné"; color: Theme.sideApplications; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
            BeeperButton { text: "×"; onClicked: { root.beeperData.replyToMessageID = ""; root.editMessageID = ""; } }
          }
          RowLayout {
            visible: !!root.beeperData.draftAttachment; Layout.fillWidth: true
            BeeperMedia { Layout.fillWidth: true; Layout.preferredHeight: 88; attachment: root.beeperData.draftAttachment || {}; beeperData: root.beeperData; playbackEnabled: root.active }
            BeeperButton { text: "×"; onClicked: root.beeperData.clearAttachment(); Accessible.name: "Retirer la pièce jointe" }
          }
          ScrollView {
            Layout.fillWidth: true; Layout.preferredHeight: Math.max(66, Math.min(200, composer.implicitHeight))
            clip: true
            TextArea {
              id: composer; objectName: "beeperComposer"
              text: root.editMessageID ? root.editText : root.beeperData.draftText
              placeholderText: root.beeperData.currentChat?.isReadOnly ? "Conversation en lecture seule" : root.dictating ? "Dictée en cours…" : "Écrire un message…"
              color: Theme.foreground; placeholderTextColor: Theme.inactive
              selectionColor: Qt.alpha(Theme.sideApplications, 0.4)
              selectedTextColor: Theme.selectedForeground
              font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.body }
              wrapMode: TextEdit.Wrap; selectByMouse: true
              background: null
              onTextChanged: {
                if (!root.active || !activeFocus) return;
                if (root.editMessageID) { if (text !== root.editText) root.editText = text; }
                else if (text !== root.beeperData.draftText) root.beeperData.draftText = text;
              }
  Keys.onPressed: event => {
                if (Format.shouldSend(event.key, event.modifiers, inputMethodComposing)) { root.submitMessage(); event.accepted = true; }
                else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier) && (!canPaste || (event.modifiers & Qt.ShiftModifier))) { root.beeperData.pasteAttachment(); event.accepted = true; }
              }
            }
          }
          RowLayout {
            Layout.fillWidth: true; spacing: 4
            BeeperButton { text: "+"; font.pixelSize: Theme.beeperFont.icon; onClicked: fileDialog.open(); Accessible.name: "Joindre un fichier" }
            BeeperButton { text: root.recording ? "■" : "󰍬"; accent: root.recording ? Theme.error : Theme.sideApplications; prominent: root.recording; enabled: !root.preparingRecording; onClicked: root.recording ? root.stopRecording() : root.startRecording(); Accessible.name: root.recording ? "Terminer le vocal" : "Enregistrer un vocal" }
            Text { visible: root.recording; text: "Enregistrement  " + Format.duration(root.recorder?.duration || 0); color: Theme.error; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
            Item { Layout.fillWidth: true }
            Text { visible: !root.compact && !root.recording; text: "Maj + Entrée  nouvelle ligne"; color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
            BeeperButton { objectName: "beeperSend"; prominent: true; text: root.beeperData.sending ? "Envoi…" : root.editMessageID ? "Enregistrer  ↵" : "Envoyer  ↵"; enabled: !root.recording && !root.preparingRecording && !root.beeperData.sending && root.beeperData.connected && (!!composer.text.trim() || !!root.beeperData.draftAttachment); onClicked: root.submitMessage() }
          }
        }
        DropArea {
          anchors.fill: parent
          onDropped: drop => { if (drop.hasUrls && drop.urls.length) { root.beeperData.stageAttachment(drop.urls[0].toString()); drop.acceptProposedAction(); } }
        }
      }
      RowLayout {
        Layout.fillWidth: true; Layout.preferredHeight: 38
        Text { text: composer.activeFocus ? "SAISIE" : root.navigation === "chats" ? "CONVERSATIONS" : "MESSAGES"; color: composer.activeFocus ? Theme.sideApplications : Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption; letterSpacing: 1 } }
        Item { Layout.fillWidth: true }
        Text { Layout.fillWidth: true; text: "h j k l  naviguer    i  écrire    :  actions    ?  aide"; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight; color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption } }
      }
    }
  }

  Rectangle {
    id: connectionSurface
    objectName: "beeperConnectionSurface"
    anchors { fill: parent; margins: 14 } radius: 20
    visible: !root.beeperData.connected && (root.beeperData.tokenRequired || root.beeperData.chats.length === 0)
    color: Qt.alpha(Theme.background, 0.97)
    MouseArea { anchors.fill: parent }
    ColumnLayout {
      anchors.centerIn: parent; width: Math.min(parent.width - 60, 440); spacing: 18
      Text {
        objectName: "beeperConnectionTitle"
        Layout.fillWidth: true; wrapMode: Text.Wrap
        text: root.beeperData.tokenRequired ? "Tes conversations,\nà ta manière."
          : root.beeperData.state === "keyring-unavailable" ? "En attente\ndu trousseau"
          : "Reconnexion\nen cours…"
        color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.hero } lineHeight: 1.1
      }
      Text {
        Layout.fillWidth: true
        text: root.beeperData.tokenRequired
          ? "Active l’API locale dans Beeper Desktop, puis colle ton jeton d’accès."
          : root.beeperData.state === "keyring-unavailable" || root.beeperData.state === "loading-token"
          ? "L’accès enregistré sera récupéré automatiquement dès que le trousseau sera disponible."
          : "Beeper Desktop doit rester ouvert avec son API locale activée. Ton accès enregistré sera réutilisé automatiquement."
        wrapMode: Text.Wrap; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label } lineHeight: 1.25
      }
      BusyIndicator { visible: !root.beeperData.tokenRequired; running: connectionSurface.visible && visible; Layout.alignment: Qt.AlignHCenter }
      TextField { id: tokenField; objectName: "beeperToken"; visible: root.beeperData.tokenRequired; enabled: !root.beeperData.savingToken; Layout.fillWidth: true; implicitHeight: 50; echoMode: TextInput.Password; placeholderText: "Jeton de l’API Beeper"; color: Theme.foreground; placeholderTextColor: Theme.inactive; selectByMouse: true; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control } background: Rectangle { radius: 10; color: Theme.surfaceRaised } onAccepted: root.beeperData.connectToken(text) }
      Text { Layout.fillWidth: true; text: root.beeperData.lastError || root.beeperData.statusMessage; wrapMode: Text.Wrap; color: root.beeperData.lastError ? Theme.error : Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      Text { visible: root.beeperData.tokenRequired; Layout.fillWidth: true; text: "Désactive aussi les notifications et les sons dans Beeper Desktop : ce panneau gère les alertes."; wrapMode: Text.Wrap; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      RowLayout {
        BeeperButton { visible: root.beeperData.tokenRequired; prominent: true; text: root.beeperData.savingToken ? "Connexion…" : "Connecter Beeper"; enabled: !root.beeperData.savingToken && !!tokenField.text.trim(); onClicked: root.beeperData.connectToken(tokenField.text) }
        BeeperButton { objectName: "beeperReconnect"; text: "Réessayer"; enabled: !root.beeperData.savingToken; onClicked: root.beeperData.retryConnection() }
        BeeperButton { text: "Fermer"; onClicked: root.closeRequested() }
      }
    }
  }

  Rectangle {
    anchors.fill: parent; visible: !!root.modal; color: Qt.alpha(Theme.background, 0.55)
    MouseArea { anchors.fill: parent; onClicked: root.closeModal() }
    Rectangle {
      id: modalSurface
      anchors.centerIn: parent
      width: Math.min(parent.width - 60, root.modal === "media" ? 760 : 540)
      height: Math.min(parent.height - 60, modalColumn.implicitHeight + 36)
      radius: 18; color: Theme.surface
      border.width: 1; border.color: Qt.alpha(Theme.foreground, 0.1)
      clip: true
      MouseArea { anchors.fill: parent }
      Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.closeModal(); event.accepted = true; }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitModal(); event.accepted = true; }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up || (!modalInput.activeFocus && (event.text === "j" || event.text === "k"))) { root.actionIndex = Math.max(0, Math.min(root.filteredActions.length - 1, root.actionIndex + (event.key === Qt.Key_Down || event.text === "j" ? 1 : -1))); event.accepted = true; }
      }
      ColumnLayout {
        id: modalColumn
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 12
        RowLayout {
          Layout.fillWidth: true
          Text { Layout.fillWidth: true; text: ({actions: "Actions", help: "Tout au clavier", react: "Ajouter une réaction", delete: "Supprimer ce message ?", new: "Nouvelle conversation", search: "Rechercher un message", media: "Pièce jointe"})[root.modal] || ""; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.title; weight: Font.Medium } }
          BeeperButton { text: "×"; onClicked: root.closeModal() }
        }
        BeeperAccountPicker { visible: root.modal === "new"; Layout.fillWidth: true; model: root.beeperData.accounts; onActivated: root.newAccountID = currentValue }
        TextField {
          id: modalInput; objectName: "beeperActionQuery"
          visible: ["actions", "react", "new", "search"].includes(root.modal)
          Layout.fillWidth: true; implicitHeight: 46
          placeholderText: root.modal === "react" ? "Emoji, par exemple ♡ ou 👍" : root.modal === "new" ? "Nom, numéro ou identifiant du contact" : "Rechercher…"
          color: Theme.foreground; placeholderTextColor: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label } selectByMouse: true
          background: Rectangle { radius: 9; color: Theme.surfaceRaised }
          onTextChanged: { root.actionIndex = 0; if (root.modal === "new") contactTimer.restart(); }
          onAccepted: root.submitModal()
          Keys.onEscapePressed: root.closeModal()
          Keys.onDownPressed: { root.actionIndex = Math.min(root.filteredActions.length - 1, root.actionIndex + 1); }
          Keys.onUpPressed: { root.actionIndex = Math.max(0, root.actionIndex - 1); }
        }
        ListView {
          visible: root.modal === "actions"
          Layout.fillWidth: true; Layout.preferredHeight: Math.min(400, contentHeight)
          clip: true; model: root.filteredActions; currentIndex: root.actionIndex
          onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
          delegate: BeeperButton {
            required property var modelData; required property int index
            width: ListView.view.width; height: 46
            text: modelData.label + (modelData.key ? "    " + modelData.key : "")
            prominent: index === root.actionIndex
            onClicked: root.runAction(modelData.id)
          }
        }
        Text {
          visible: root.modal === "help"; Layout.fillWidth: true
          text: "h / l     Conversations / messages\nj / k     Message ou conversation suivante / précédente\ngg / G     Début / fin de la liste\nCtrl + d / u     Défiler d’une demi-page\n/     Filtrer les conversations\ni     Écrire un message\n: ou Ctrl + k     Toutes les actions\nr / e / o     Répondre / modifier / ouvrir un média\nEntrée     Envoyer le message\nMaj + Entrée     Nouvelle ligne\nCtrl + Maj + v     Coller une pièce jointe\nÉchap     Quitter la saisie, fermer le dialogue, puis replier"
          color: Theme.secondary; wrapMode: Text.Wrap; lineHeight: 1.65; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
        }
        Text { visible: root.modal === "delete"; Layout.fillWidth: true; text: "Cette action sera transmise au réseau. Le message peut être supprimé pour tous les participants."; color: Theme.secondary; wrapMode: Text.Wrap; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control } }
        ListView {
          visible: root.modal === "search" || root.modal === "new"
          Layout.fillWidth: true; Layout.preferredHeight: Math.min(330, contentHeight)
          clip: true
          model: root.modal === "new" ? root.contacts : root.beeperData.searchResults
          delegate: BeeperButton {
            required property var modelData
            width: ListView.view.width; height: 50
            text: root.modal === "new" ? modelData.fullName || modelData.displayName || modelData.username || modelData.id : (modelData.senderName || "Message") + "  ·  " + (modelData.text || "Pièce jointe")
            onClicked: { if (root.modal === "new") root.startChat(modelData.id); else { root.openChat(modelData.chatID, modelData.id); root.closeModal(); } }
          }
        }
        BeeperMedia { visible: root.modal === "media"; Layout.fillWidth: true; Layout.preferredHeight: root.modal === "media" ? implicitHeight : 0; attachment: root.previewAttachment || {}; beeperData: root.beeperData; expanded: true; playbackEnabled: root.modal === "media" && root.active }
        RowLayout {
          visible: ["react", "delete", "new", "search"].includes(root.modal)
          Item { Layout.fillWidth: true }
          BeeperButton { text: "Annuler"; onClicked: root.closeModal() }
          BeeperButton { prominent: true; accent: root.modal === "delete" ? Theme.error : Theme.sideApplications; text: root.modal === "delete" ? "Supprimer" : root.modal === "search" ? "Rechercher" : "Valider"; onClicked: root.submitModal() }
        }
      }
    }
  }
}
