import QtQuick
import QtTest
import Quickshell

// Isolated transport and fictional accounts: no real service is disconnected.
ShellRoot {
  id: fixture
  property var beeperData: null
  property var panel: null
  Window { id: window; width: 1280; height: 900; visible: true }
  TestResult { id: results }
  TestCase {
    name: "BeeperConnections"
    when: window.visible
    function create(file, parent, props) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + file);
      compare(component.status, Component.Ready, component.errorString());
      const item = component.createObject(parent, props);
      verify(item !== null); return item;
    }
    function child(name) { return findChild(panel, name); }
    function pending() { return beeperData.requests.filter(request => request.method === "accounts"); }
    function setStatus(id, status) {
      beeperData.accounts = beeperData.accounts.map(account => (account.accountID || account.id) === id
        ? Object.assign({}, account, {status: status}) : account);
    }
    function init() {
      beeperData = create("fixtures/PagedBeeperData.qml", fixture, {});
      beeperData.accounts = [
        {accountID: "wa-personal", network: "WhatsApp", status: "connected"},
        {accountID: "wa-work", network: "WhatsApp", status: "connected"},
        {id: "telegram", network: "Telegram", status: "connected"}
      ];
      beeperData.chats = [
        {id: "personal", title: "Camille", type: "single", accountID: "wa-personal", network: "WhatsApp"},
        {id: "work", title: "Work", type: "single", accountID: "wa-work", network: "WhatsApp"},
        {id: "telegram-chat", title: "Léa", type: "single", accountID: "telegram", network: "Telegram"}
      ];
      panel = create("../features/messenger/BeeperPanel.qml", window.contentItem,
        {beeperData: beeperData, width: 1280, height: 900, active: true, windowFocused: true});
      beeperData.selectChat("personal");
      beeperData.respond("messages", {items: [{id: "sent", chatID: "personal", text: "A fictional reply", isSender: true}], hasMore: false});
      tryCompare(panel, "restoringView", false); wait(30);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
      panel.active = false; panel.destroy(); beeperData.destroy(); wait(0);
    }
    function cleanupTestCase() {
      console.log("BeeperConnections: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function test_failure_colors_only_affected_accounts_and_recovers_existing_bubbles() {
      const history = child("beeperMessages"), message = history.itemAtIndex(0);
      const normal = panel.conversationAccent;
      const unaffected = child("beeperChatRow-work").platformAccent;
      verify(!child("beeperNetworkConnectionWarning").visible);
      setStatus("wa-personal", "disconnected");
      compare(panel.conversationAccent.toString(), "#ed8796");
      compare(child("beeperChatRow-personal").platformAccent.toString(), "#ed8796");
      compare(child("beeperChatRow-work").platformAccent, unaffected);
      compare(message.bubbleColor.toString(), "#ed8796");
      compare(child("beeperComposerSurface").networkAccent.toString(), "#ed8796");
      compare(findChild(child("beeperHeaderAvatar"), "beeperNetworkBadge").color.toString(), "#ed8796");
      compare(findChild(child("beeperChatAvatar-personal"), "beeperNetworkBadge").color.toString(), "#ed8796");
      verify(child("beeperNetworkConnectionWarning").visible);
      setStatus("wa-personal", "connected");
      compare(panel.conversationAccent, normal); compare(message.bubbleColor, normal);
      verify(!child("beeperNetworkConnectionWarning").visible);
      compare(history.itemAtIndex(0), message, "Recovery must not recreate message/media delegates");
    }
    function test_network_warning_aggregates_accounts_and_all_filter() {
      setStatus("wa-work", "reconnect_required");
      verify(child("beeperNetworkConnectionWarning").visible, "All warns about any affected network");
      verify(!panel.conversationConnectionIssue, "A second account must not recolor a healthy account");
      beeperData.networkFilter = "telegram";
      verify(!child("beeperNetworkConnectionWarning").visible);
      beeperData.networkFilter = "whatsapp";
      verify(child("beeperNetworkConnectionWarning").visible);
      setStatus("wa-work", "connected");
      verify(!child("beeperNetworkConnectionWarning").visible);
      setStatus("telegram", "attention_required"); beeperData.networkFilter = "telegram";
      verify(child("beeperNetworkConnectionWarning").visible, "Legacy account IDs remain supported");
    }
    function test_only_connection_statuses_affect_accents() {
      for (const status of ["connecting", "connection_required", "reconnect_required", "attention_required", "disconnected", "disabled"]) {
        setStatus("wa-personal", status);
        verify(!!panel.conversationConnectionIssue, status);
      }
      for (const status of ["connected", "backfilling", "", "future_status", "toString"]) {
        setStatus("wa-personal", status);
        verify(!panel.conversationConnectionIssue, status);
      }
      beeperData.lastError = "An unrelated attachment failed";
      verify(!child("beeperNetworkConnectionWarning").visible);
    }
    function test_service_outage_colors_all_networks_until_reconnected() {
      for (const state of ["offline", "connecting", "loading-token", "needs-token", "invalid-token", "keyring-unavailable"]) {
        beeperData.state = state;
        for (const id of ["personal", "work", "telegram-chat"])
          compare(child("beeperChatRow-" + id).platformAccent.toString(), "#ed8796", state);
        verify(child("beeperNetworkConnectionWarning").visible, state);
      }
      beeperData.state = "connected";
      verify(!panel.conversationConnectionIssue); verify(!child("beeperNetworkConnectionWarning").visible);
    }
    function test_account_refresh_deduplicates_and_keeps_issues_on_failed_poll() {
      const healthy = beeperData.accounts;
      setStatus("wa-personal", "disconnected");
      beeperData.refreshAccounts(); beeperData.refreshAccounts();
      compare(pending().length, 1); verify(pending()[0].quiet);
      beeperData.respond("accounts", null, {message: "Temporary API error"});
      verify(!beeperData.loadingAccounts); verify(!!panel.conversationConnectionIssue);
      compare(beeperData.lastError, "");
      beeperData.refreshAccounts(); beeperData.respond("accounts", {});
      verify(!!panel.conversationConnectionIssue, "A malformed response must not clear the last known failure");
      beeperData.refreshAccounts(); beeperData.respond("accounts", {items: healthy});
      verify(!panel.conversationConnectionIssue);
      beeperData.refreshAccounts(); beeperData.respond("accounts", healthy.map(account => Object.assign({}, account, {status: "disconnected"})));
      verify(!!panel.conversationConnectionIssue, "The official top-level array response is accepted too");
    }
    function test_old_account_response_cannot_clear_a_new_connection_failure() {
      const healthy = beeperData.accounts;
      setStatus("wa-personal", "disconnected");
      beeperData.refreshAccounts();
      beeperData.state = "offline"; beeperData.state = "connected";
      beeperData.refreshAccounts(); compare(pending().length, 2);
      beeperData.respond("accounts", healthy);
      verify(beeperData.loadingAccounts, "The new request remains in flight");
      verify(!!panel.conversationConnectionIssue);
      beeperData.respond("accounts", healthy);
      verify(!beeperData.loadingAccounts); verify(!panel.conversationConnectionIssue);
    }
  }
}
