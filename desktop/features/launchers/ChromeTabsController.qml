import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "LauncherSearch.js" as Search
import "LauncherWindows.js" as Windows

Scope {
  id: root

  property var toplevels: Hyprland.toplevels.values
  property string query: ""
  property int selectedIndex: 0
  property bool loading: false
  property string message: ""
  property string action: ""
  property string actionTabId: ""
  property var actionTab: null
  property var actionToplevel: null
  readonly property bool actionPending: action !== ""
  property var catalog: []
  property var results: []
  signal closeRequested()

  onQueryChanged: refreshResults()

  function toplevelFor(tab) {
    return Windows.forTab(tab, catalog, toplevels);
  }

  function focusToplevel(toplevel) {
    Windows.focus(toplevel, command => Hyprland.dispatch(command));
  }

  function refreshResults() {
    const query = Search.normalizeText(root.query.trim());
    if (query === "") {
      results = catalog.slice();
    } else {
      const ranked = [];
      for (let index = 0; index < catalog.length; ++index) {
        const candidate = catalog[index];
        const score = Search.fuzzyScore(candidate, query);
        if (score >= 0)
          ranked.push({ "candidate": candidate, "score": score });
      }
      ranked.sort((left, right) => right.score - left.score
        || left.candidate.tab.title.localeCompare(right.candidate.tab.title));
      results = ranked.map(result => result.candidate);
    }
    selectedIndex = 0;
  }

  function parseResponse(text) {
    loading = false;
    try {
      const response = JSON.parse(text.trim());
      if (!response.ok) {
        catalog = [];
        message = response.error || "Unable to contact Chrome";
        refreshResults();
        return;
      }

      const tabs = Array.isArray(response.tabs) ? response.tabs : [];
      catalog = tabs.filter(tab => tab.id !== undefined)
        .map(tab => {
          const title = (tab.title || tab.url || "Untitled tab").toString();
          const url = (tab.url || "").toString();
          return {
            "tab": tab,
            "normalizedName": Search.normalizeText(title),
            "searchText": Search.normalizeText(title + " " + url)
          };
        });
      message = "";
      refreshResults();
    } catch (error) {
      catalog = [];
      message = "Unable to read Chrome tabs";
      refreshResults();
    }
  }

  function requestTabs() {
    if (chromeTabsProcess.running)
      return;
    loading = true;
    message = "";
    catalog = [];
    refreshResults();
    chromeTabsProcess.running = true;
  }

  function setQuery(query) {
    root.query = query;
  }

  function moveSelection(delta) {
    if (results.length === 0)
      return;
    selectedIndex = (selectedIndex + delta
      + results.length) % results.length;
  }

  function runAction(requestedAction, tab) {
    if (actionPending)
      return;
    if (tab === null || tab === undefined || tab.id === undefined)
      return;
    action = requestedAction;
    actionTabId = tab.id.toString();
    actionTab = tab;
    actionToplevel = requestedAction === "activate"
      ? toplevelFor(tab) : null;
    message = "";
    if (requestedAction === "activate")
      chromeTabsActivationDelay.restart();
    else
      chromeTabsActionProcess.exec([
        "quickshell-chrome-tabs", action, actionTabId
      ]);
  }

  function activateSelected(index = selectedIndex) {
    if (loading || results.length === 0)
      return;
    const boundedIndex = Math.max(0, Math.min(index,
      results.length - 1));
    runAction("activate", results[boundedIndex].tab);
  }

  function closeSelected(index = selectedIndex) {
    if (loading || results.length === 0)
      return;
    const boundedIndex = Math.max(0, Math.min(index,
      results.length - 1));
    runAction("close", results[boundedIndex].tab);
  }

  function parseActionResponse(text) {
    const completedAction = action;
    const tabId = actionTabId;
    const completedTab = actionTab;
    const completedToplevel = actionToplevel;
    action = "";
    actionTabId = "";
    actionTab = null;
    actionToplevel = null;
    try {
      const response = JSON.parse(text.trim());
      if (!response.ok) {
        catalog = [];
        message = response.error || "Chrome tab action failed";
        refreshResults();
        return;
      }
      if (completedAction === "activate") {
        closeRequested();
        Qt.callLater(() => {
          const target = completedToplevel !== null
            ? completedToplevel : toplevelFor(completedTab);
          focusToplevel(target);
        });
      } else if (completedAction === "close") {
        const previousIndex = selectedIndex;
        catalog = catalog.filter(candidate =>
          candidate.tab.id !== tabId);
        refreshResults();
        if (results.length > 0)
          selectedIndex = Math.min(previousIndex,
            results.length - 1);
      }
    } catch (error) {
      catalog = [];
      message = "Unable to complete Chrome tab action";
      refreshResults();
    }
  }

  Process {
    id: chromeTabsProcess
    command: ["quickshell-chrome-tabs", "list"]

    stdout: StdioCollector {
      onStreamFinished: root.parseResponse(text)
    }
  }

  // Give the compositor one frame to release the layer-shell exclusive
  // keyboard grab before Chrome requests focus for the selected window.
  Timer {
    id: chromeTabsActivationDelay
    interval: 50
    repeat: false
    onTriggered: chromeTabsActionProcess.exec([
      "quickshell-chrome-tabs", root.action,
      root.actionTabId
    ])
  }

  Process {
    id: chromeTabsActionProcess

    stdout: StdioCollector {
      onStreamFinished: root.parseActionResponse(text)
    }
  }

}
