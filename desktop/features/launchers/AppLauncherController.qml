import Quickshell
import Quickshell.Hyprland
import QtQuick
import "LauncherSearch.js" as Search
import "LauncherWindows.js" as Windows

Scope {
  id: root

  // Catalog/search state belongs to the launcher; surface ownership stays in shell/.
  property var applications: DesktopEntries.applications.values
  property var toplevels: Hyprland.toplevels.values
  property string query: ""
  property int selectedIndex: 0
  property int toplevelRevision: 0
  property var catalog: []
  property var results: []
  signal closeRequested()

  onApplicationsChanged: rebuildCatalog()
  onToplevelsChanged: ++toplevelRevision
  onQueryChanged: refreshResults()
  Component.onCompleted: rebuildCatalog()

  function toplevelFor(entry) {
    return Windows.forApp(entry, toplevels);
  }

  function focusToplevel(toplevel) {
    Windows.focus(toplevel, command => Hyprland.dispatch(command));
  }

  function rebuildCatalog() {
    const catalog = [];
    for (let index = 0; index < applications.length; ++index) {
      const entry = applications[index];
      if (entry.noDisplay || entry.name === "")
        continue;
      const keywords = entry.keywords !== undefined
        ? entry.keywords.join(" ") : "";
      const normalizedName = Search.normalizeText(entry.name);
      catalog.push({
        "entry": entry,
        "normalizedName": normalizedName,
        "searchText": Search.normalizeText(entry.name + " " + entry.genericName
          + " " + keywords + " " + entry.comment)
      });
    }
    catalog.sort((left, right) => left.entry.name.localeCompare(right.entry.name));
    root.catalog = catalog;
    refreshResults();
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
        || left.candidate.entry.name.localeCompare(right.candidate.entry.name));
      results = ranked.map(result => result.candidate);
    }
    selectedIndex = 0;
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

  function launchNewInstance(entry) {
    const newWindowAction = entry.actions.find(action => {
      const id = Search.normalizeIdentity(action.id);
      const name = Search.normalizeText(action.name).trim();
      return id === "new-window" || id === "newwindow"
        || name === "new window" || name === "nouvelle fenetre";
    });
    if (newWindowAction !== undefined)
      newWindowAction.execute();
    else
      entry.execute();
  }

  function launchSelected(index = selectedIndex, forceNew = false) {
    if (results.length === 0)
      return;
    const boundedIndex = Math.max(0, Math.min(index,
      results.length - 1));
    const entry = results[boundedIndex].entry;
    const runningToplevel = forceNew ? null : toplevelFor(entry);
    closeRequested();
    if (runningToplevel !== null) {
      focusToplevel(runningToplevel);
    } else if (forceNew) {
      launchNewInstance(entry);
    } else {
      entry.execute();
    }
  }

}
