import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Rectangle {
  id: root
  objectName: "beeperNewChat"
  required property var beeperData
  property bool opened: false
  property bool active: false
  property string preferredNetwork: "all"
  property var contacts: []
  property bool searching: false
  property bool starting: false
  property string errorText: ""
  property int searchRevision: 0
  property int sessionRevision: 0
  property bool choosingNetwork: true
  readonly property var accounts: beeperData.accounts.map(account => ({
    id: account.accountID || account.id, network: account.network || "Beeper"
  })).filter(account => !!account.id)
  readonly property string accountID: accounts[accountPicker.currentIndex]?.id || ""
  readonly property string network: accounts[accountPicker.currentIndex]?.network || ""
  readonly property color networkAccent: Theme.beeperNetworkColors[Format.networkBadge(network).key] || Theme.secondary
  readonly property string query: contactInput.text.trim()
  readonly property var directUser: {
    const phone = query.replace(/[\s().-]/g, "").replace(/^00/, "+");
    if (/^\+[1-9]\d{6,14}$/.test(phone)) return {phoneNumber: phone};
    if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(query)) return {email: query};
    if (/^@[^\s@]+$/.test(query)) return {username: query};
    return null;
  }
  signal closeRequested()
  signal chatStarted(var chat)
  visible: opened
  enabled: active && opened
  color: Qt.alpha(Theme.background, 0.65)
  onOpenedChanged: {
    ++sessionRevision;
    if (opened) {
      choosingNetwork = true;
      contactInput.text = ""; errorText = "";
      const preferred = accounts.findIndex(account => Format.networkBadge(account.network).key === preferredNetwork);
      accountPicker.currentIndex = preferred >= 0 ? preferred : accounts.length ? 0 : -1;
      Qt.callLater(() => { if (opened && active) (accountPicker.enabled ? accountPicker : closeButton).forceActiveFocus(); });
    }
    queueSearch();
  }
  onAccountIDChanged: queueSearch()
  onQueryChanged: queueSearch()
  onChoosingNetworkChanged: queueSearch()
  function chooseNetwork() {
    if (!opened || !active || starting || !accountID) return;
    choosingNetwork = false;
    contactInput.forceActiveFocus();
  }
  function backToNetworks() {
    if (starting) return;
    choosingNetwork = true;
    accountPicker.forceActiveFocus();
  }
  function handleEscape() {
    if (choosingNetwork || starting) closeRequested();
    else backToNetworks();
  }
  function queueSearch() {
    ++searchRevision; searchTimer.stop(); contacts = []; searching = false; errorText = "";
    if (opened && !choosingNetwork && accountID && query && !starting) { searching = true; searchTimer.restart(); }
  }
  function search() {
    const revision = searchRevision;
    beeperData.request("contacts", {accountID: accountID, query: query}, (result, error) => {
      if (revision !== searchRevision || !opened) return;
      searching = false;
      if (error) { errorText = error.message || "Contact search unavailable."; return; }
      contacts = result?.items || [];
      contactList.currentIndex = contacts.findIndex(user => !user.cannotMessage);
    }, true);
  }
  function start(user) {
    if (!opened || !active || choosingNetwork || starting || !accountID || !user || user.cannotMessage) return;
    const candidate = {};
    for (const key of ["id", "phoneNumber", "username", "email", "fullName"])
      if (user[key]) candidate[key] = user[key];
    const session = sessionRevision;
    ++searchRevision; searchTimer.stop(); searching = false; starting = true; errorText = "";
    beeperData.startChat(accountID, candidate, (chat, error) => {
      starting = false;
      if (session !== sessionRevision || !opened || !active) return;
      if (error) { errorText = error.message || "Unable to open this conversation."; return; }
      chatStarted(chat);
    });
  }
  function accept() {
    if (searching || starting) return;
    if (contacts[contactList.currentIndex]) start(contacts[contactList.currentIndex]);
    else if (!contacts.length) start(directUser);
  }
  Timer { id: searchTimer; interval: 300; onTriggered: root.search() }
  MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
  FocusScope {
    anchors.centerIn: parent
    width: Math.min(560, parent.width - 40)
    height: Math.min(parent.height - 40, content.implicitHeight + 36)
    Rectangle { anchors.fill: parent; radius: 18; color: Theme.surface; MouseArea { anchors.fill: parent } }
    Keys.onEscapePressed: event => { root.handleEscape(); event.accepted = true; }
    ColumnLayout {
      id: content
      anchors { fill: parent; margins: 18 }
      spacing: 12
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true; text: "New conversation"; color: Theme.foreground
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.title; weight: Font.Medium }
        }
        BeeperButton { id: closeButton; iconName: "x"; Accessible.name: "Close"; onClicked: root.closeRequested() }
      }
      BeeperAccountPicker {
        id: accountPicker; objectName: "beeperNewChatAccount"
        visible: root.choosingNetwork
        Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight, Math.max(64, root.height - 160))
        model: root.accounts
        enabled: !root.starting && root.accounts.length > 0
        Accessible.name: "Messaging network"
        onActivated: root.chooseNetwork()
      }
      BeeperButton {
        objectName: "beeperNewChatNetworkBack"
        implicitHeight: 52
        Layout.fillWidth: true; visible: !root.choosingNetwork; enabled: !root.starting
        accent: root.networkAccent; prominent: true
        Accessible.name: "Change network"
        onClicked: root.backToNetworks()
        contentItem: RowLayout {
          spacing: 12
          Icon { name: "arrow-left"; size: 18; color: root.networkAccent }
          BeeperNetworkBadge {
            network: root.network; showsName: false
            Layout.preferredWidth: 32; Layout.preferredHeight: 32
          }
          Text {
            Layout.fillWidth: true; text: Format.networkBadge(root.network).name
            color: root.networkAccent; textFormat: Text.PlainText; elide: Text.ElideRight
            font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.label }
          }
        }
      }
      TextField {
        id: contactInput; objectName: "beeperNewChatInput"
        visible: !root.choosingNetwork
        Layout.fillWidth: true; implicitHeight: 46
        enabled: !root.choosingNetwork && !root.starting && !!root.accountID
        placeholderText: "Name, +33612345678, @username or email"
        Accessible.name: "Contact or new recipient"
        color: Theme.foreground; placeholderTextColor: Theme.inactive; selectByMouse: true
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
        background: Rectangle { radius: 8; color: Theme.surfaceRaised }
        Keys.onPressed: event => {
          if (inputMethodComposing) return;
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            event.accepted = true; if (!event.isAutoRepeat) root.accept();
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            contactList.currentIndex = Math.max(0, Math.min(root.contacts.length - 1,
              contactList.currentIndex + (event.key === Qt.Key_Down ? 1 : -1)));
            event.accepted = true;
          }
        }
      }
      Text {
        visible: !root.choosingNetwork || !root.accounts.length
        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.secondary
        text: !root.accounts.length ? "No messaging account available."
          : "Use a number with its country code or @username to find someone you have never messaged. Availability depends on the network."
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
      }
      Text {
        Layout.fillWidth: true; visible: !root.choosingNetwork && (root.searching || root.starting || !!root.query && !root.contacts.length)
        text: root.starting ? "Opening conversation…" : root.searching ? "Searching…" : "No contacts found."
        color: Theme.secondary; font.pixelSize: Theme.beeperFont.secondary
      }
      ListView {
        id: contactList; objectName: "beeperNewChatContacts"
        visible: !root.choosingNetwork
        Layout.fillWidth: true; Layout.preferredHeight: Math.min(contentHeight, 230)
        Layout.minimumHeight: 0
        model: root.contacts; clip: true; spacing: 4; enabled: !root.starting
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        AcceleratedScroll { flickable: contactList }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: BeeperButton {
          required property var modelData
          required property int index
          width: contactList.width; height: 66
          enabled: !modelData.cannotMessage
          prominent: index === contactList.currentIndex
          onClicked: root.start(modelData)
          Accessible.name: modelData.fullName || modelData.username || modelData.phoneNumber || modelData.id
          contentItem: Column {
            spacing: 3
            Text {
              width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
              text: modelData.fullName || modelData.username || modelData.phoneNumber || modelData.email || modelData.id
              color: modelData.cannotMessage ? Theme.inactive : Theme.foreground; font.pixelSize: Theme.beeperFont.secondary
            }
            Text {
              width: parent.width; elide: Text.ElideRight; textFormat: Text.PlainText
              text: modelData.cannotMessage ? "This contact cannot be messaged on this network"
                : [modelData.username, modelData.phoneNumber, modelData.email].filter(Boolean).join(" · ")
              color: Theme.secondary; font.pixelSize: Theme.beeperFont.caption
            }
          }
        }
      }
      BeeperButton {
        objectName: "beeperNewChatDirect"
        Layout.fillWidth: true; visible: !root.choosingNetwork && !!root.directUser; enabled: !root.starting && !!root.accountID
        text: "Open conversation with " + root.query; prominent: true
        onClicked: root.start(root.directUser)
      }
      Text {
        objectName: "beeperNewChatError"
        Layout.fillWidth: true; visible: !root.choosingNetwork && !!root.errorText; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: root.errorText; color: Theme.error; font.pixelSize: Theme.beeperFont.secondary
      }
    }
  }
}
