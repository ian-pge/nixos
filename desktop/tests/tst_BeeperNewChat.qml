import QtQuick
import QtTest
import Quickshell

// In-memory transport only; never opens or messages a real contact.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  property var dialog: null
  property var input: null
  Window { id: window; width: 1280; height: 900; visible: true }
  TestResult { id: results }
  TestCase {
    name: "BeeperNewChat"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props); verify(item !== null); return item;
    }
    function pending(method) { return beeperData.requests.filter(request => request.method === method); }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      beeperData.accounts = [{accountID: "wa", network: "WhatsApp", user: {fullName: "My account"}}, {id: "tg", network: "Telegram"}];
      beeperData.replaceChats([{id: "old", title: "Existing", network: "WhatsApp", unreadCount: 2}]);
      beeperData.selectChat("old"); beeperData.respond("messages", {items: [], hasMore: false});
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {width: 1280, height: 900, beeperData: beeperData, active: true, windowFocused: true});
      dialog = findChild(panel, "beeperNewChat"); input = findChild(panel, "beeperNewChatInput");
      panel.focusNavigation(); wait(20);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperNewChat: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function openNetworks() {
      keyClick(Qt.Key_N, Qt.ControlModifier); tryCompare(panel, "modal", "newChat");
      tryVerify(() => findChild(panel, "beeperNewChatAccount").activeFocus);
    }
    function open() { openNetworks(); keyClick(Qt.Key_Return); tryVerify(() => input.activeFocus); }
    function search(text) { input.text = text; tryVerify(() => pending("contacts").length > 0); }
    function test_network_selection_owns_j_k_and_enter_before_contact_input() {
      openNetworks();
      const picker = findChild(panel, "beeperNewChatAccount");
      compare(dialog.choosingNetwork, true); verify(!input.visible);
      compare(picker.currentIndex, 0);
      compare(picker.itemAtIndex(0).network.name, "WhatsApp");
      compare(picker.itemAtIndex(1).network.name, "Telegram");
      verify(picker.itemAtIndex(0).accent !== picker.itemAtIndex(1).accent);
      keyClick(Qt.Key_J); compare(picker.currentIndex, 1);
      keyClick(Qt.Key_J); compare(picker.currentIndex, 0);
      keyClick(Qt.Key_K); compare(picker.currentIndex, 1);
      compare(input.text, ""); compare(pending("contacts").length, 0);
      keyClick(Qt.Key_Return); tryVerify(() => input.activeFocus);
      compare(dialog.accountID, "tg"); compare(dialog.choosingNetwork, false);
      compare(pending("startChat").length, 0);
      keyClick(Qt.Key_J); keyClick(Qt.Key_K); compare(input.text, "jk");
      keyClick(Qt.Key_Escape); verify(picker.activeFocus); verify(!input.visible);
      compare(picker.currentIndex, 1); compare(input.text, "jk");
      keyClick(Qt.Key_K); keyClick(Qt.Key_Return); tryVerify(() => input.activeFocus);
      compare(dialog.accountID, "wa"); compare(input.text, "jk");
    }
    function test_shortcut_preserves_draft_and_escape_restores_navigation() {
      beeperData.draftText = "Unsent draft";
      panel.compose(); open();
      compare(dialog.accountID, "wa"); compare(pending("startChat").length, 0);
      keyClick(Qt.Key_Escape); verify(dialog.choosingNetwork);
      keyClick(Qt.Key_Escape); compare(panel.modal, "");
      compare(beeperData.currentChatID, "old"); compare(beeperData.draftText, "Unsent draft");
      compare(pending("send").length, 0); compare(pending("read").length, 0);
    }
    function test_button_uses_current_network_and_accepts_phone_without_existing_contact() {
      beeperData.networkFilter = "telegram";
      mouseClick(findChild(panel, "beeperNewChatButton"));
      const picker = findChild(panel, "beeperNewChatAccount");
      tryVerify(() => picker.activeFocus); compare(picker.currentIndex, 1);
      mouseClick(picker.itemAtIndex(1)); tryVerify(() => input.activeFocus);
      compare(dialog.accountID, "tg");
      search("+33 (6) 12 34 56 78"); beeperData.respond("contacts", {items: []});
      keyClick(Qt.Key_Return); keyClick(Qt.Key_Return);
      compare(pending("startChat").length, 1);
      compare(pending("startChat")[0].params, {accountID: "tg", user: {phoneNumber: "+33612345678"}});
      beeperData.respond("startChat", {id: "new", accountID: "tg", network: "Telegram", title: "New person", type: "single", unreadCount: 0});
      compare(panel.modal, ""); compare(beeperData.currentChatID, "new");
      verify(beeperData.chats.some(chat => chat.id === "new")); verify(panel.composer.activeFocus);
      compare(pending("send").length, 0); compare(pending("read").length, 0);
    }
    function test_typed_identifiers_and_name_only_search() {
      open();
      for (const entry of [["@new.person", {username: "@new.person"}], ["alice@example.org", {email: "alice@example.org"}], ["0033612345678", {phoneNumber: "+33612345678"}], ["Alice Dupont", null], ["0612345678", null]]) {
        input.text = entry[0]; compare(dialog.directUser, entry[1]);
      }
    }
    function test_search_discards_previous_account_and_query_results() {
      open(); search("Alice");
      keyClick(Qt.Key_Escape); keyClick(Qt.Key_J); keyClick(Qt.Key_Return);
      input.text = "@bob";
      beeperData.respond("contacts", {items: [{id: "wrong", fullName: "Alice"}]});
      compare(dialog.contacts.length, 0);
      tryVerify(() => pending("contacts").length > 0);
      compare(pending("contacts")[0].params, {accountID: "tg", query: "@bob"});
      beeperData.respond("contacts", {items: [{id: "bob", fullName: "Bob"}]});
      keyClick(Qt.Key_Return);
      compare(pending("startChat")[0].params.user.id, "bob");
    }
    function test_blocked_contact_and_api_error_do_not_change_chat() {
      open(); search("Alex");
      beeperData.respond("contacts", {items: [{id: "blocked", fullName: "Alex", cannotMessage: true}]});
      keyClick(Qt.Key_Return); compare(pending("startChat").length, 0);
      input.text = "@alex"; mouseClick(findChild(panel, "beeperNewChatDirect"));
      compare(pending("startChat").length, 1);
      beeperData.respond("startChat", null, {message: "Network does not support this contact"});
      compare(dialog.errorText, "Network does not support this contact"); compare(panel.modal, "newChat");
      compare(beeperData.currentChatID, "old"); compare(input.text, "@alex");
    }
    function test_late_open_response_updates_list_without_stealing_focus() {
      open(); input.text = "@alex"; dialog.start(dialog.directUser);
      keyClick(Qt.Key_Escape); panel.compose();
      beeperData.respond("startChat", {id: "late", network: "WhatsApp", title: "Alex"});
      compare(beeperData.currentChatID, "old"); compare(panel.modal, "");
      verify(panel.composer.activeFocus); verify(beeperData.chats.some(chat => chat.id === "late"));
    }
    function test_existing_chat_is_reused_without_losing_unread_state() {
      open(); input.text = "@known"; dialog.start(dialog.directUser);
      beeperData.respond("startChat", {chatID: "old"});
      compare(beeperData.chats.length, 1); compare(beeperData.currentChat.unreadCount, 2);
      compare(pending("send").length, 0); compare(pending("read").length, 0);
    }
    function test_missing_chat_id_keeps_dialog_and_does_not_open_undefined() {
      open(); input.text = "@alex"; dialog.start(dialog.directUser);
      beeperData.respond("startChat", {});
      verify(dialog.errorText.length > 0); compare(panel.modal, "newChat"); compare(beeperData.currentChatID, "old");
    }
    function test_no_account_disables_creation() {
      beeperData.accounts = []; keyClick(Qt.Key_N, Qt.ControlModifier); tryCompare(panel, "modal", "newChat");
      verify(!input.enabled); compare(dialog.accountID, "");
      dialog.start({username: "@alex"}); compare(pending("startChat").length, 0);
      wait(10); keyClick(Qt.Key_Escape); compare(panel.modal, "");
    }
  }
}
