.pragma library
.import "LauncherSearch.js" as Search

// Window matching is pure; dispatch is injected only when focusing a result.
function forApp(entry, toplevels) {
  const appIdentities = [];
  [entry.id, entry.startupClass, entry.icon].forEach(value => {
    Search.identityAliases(value).forEach(identity => {
      if (!appIdentities.includes(identity))
        appIdentities.push(identity);
    });
  });
  if (appIdentities.length === 0)
    return null;

  let best = null;
  let bestHistory = Number.MAX_SAFE_INTEGER;
  for (let index = 0; index < toplevels.length; ++index) {
    const toplevel = toplevels[index];
    const ipc = toplevel.lastIpcObject ?? {};
    const windowIdentities = [];
    [ipc["class"], ipc.initialClass,
      toplevel.wayland !== null ? toplevel.wayland.appId : ""].forEach(value => {
      Search.identityAliases(value).forEach(identity => {
        if (!windowIdentities.includes(identity))
          windowIdentities.push(identity);
      });
    });
    if (!windowIdentities.some(identity => appIdentities.includes(identity)))
      continue;
    if (toplevel.activated)
      return toplevel;
    const focusHistory = ipc.focusHistoryID !== undefined
      ? Number(ipc.focusHistoryID) : Number.MAX_SAFE_INTEGER;
    if (best === null || focusHistory < bestHistory) {
      best = toplevel;
      bestHistory = focusHistory;
    }
  }
  return best;
}
function focus(toplevel, dispatch) {
  if (toplevel === null)
    return;
  if (toplevel.address !== "") {
    const address = toplevel.address.startsWith("0x")
      ? toplevel.address : "0x" + toplevel.address;
    dispatch('hl.dsp.focus({ window = "address:'
      + address + '" })');
  } else if (toplevel.wayland !== null) {
    toplevel.wayland.activate();
  }
}

function forTab(tab, catalog, toplevels) {
  if (tab === null || tab === undefined)
    return null;

  const relatedTabs = [];
  if (tab.windowId !== undefined) {
    for (let index = 0; index < catalog.length; ++index) {
      const candidate = catalog[index].tab;
      if (candidate.id !== tab.id && candidate.active
          && candidate.windowId === tab.windowId)
        relatedTabs.push(candidate);
    }
  }
  if (tab.active || relatedTabs.length === 0)
    relatedTabs.push(tab);

  const tabTitles = [];
  const hostTokens = [];
  for (let index = 0; index < relatedTabs.length; ++index) {
    const relatedTab = relatedTabs[index];
    const title = Search.normalizeText(relatedTab.title || "").trim();
    if (title !== "" && !tabTitles.includes(title))
      tabTitles.push(title);

    const url = (relatedTab.url || "").toString();
    const hostname = url.replace(/^[a-z][a-z0-9+.-]*:\/\//i, "")
      .split(/[\/:?#]/)[0];
    const tokens = hostname.split(".");
    for (let tokenIndex = 0; tokenIndex < tokens.length; ++tokenIndex) {
      const token = Search.normalizeText(tokens[tokenIndex]).trim();
      if (token.length >= 4
          && !["www", "com", "org", "net", "app"].includes(token)
          && !hostTokens.includes(token))
        hostTokens.push(token);
    }
  }

  let best = null;
  let bestScore = -1;
  for (let index = 0; index < toplevels.length; ++index) {
    const toplevel = toplevels[index];
    const ipc = toplevel.lastIpcObject ?? {};
    const identity = Search.normalizeText([
      ipc["class"], ipc.initialClass,
      toplevel.wayland !== null ? toplevel.wayland.appId : ""
    ].join(" "));
    if (!["chrome", "chromium", "brave", "vivaldi"].some(name =>
        identity.includes(name)))
      continue;

    const windowTitles = [toplevel.title, ipc.title, ipc.initialTitle]
      .map(title => Search.normalizeText(title || "").trim())
      .filter((title, titleIndex, titles) =>
        title !== "" && titles.indexOf(title) === titleIndex);
    let score = -1;
    for (let titleIndex = 0; titleIndex < windowTitles.length; ++titleIndex) {
      const windowTitle = windowTitles[titleIndex];
      for (let tabIndex = 0; tabIndex < tabTitles.length; ++tabIndex) {
        const tabTitle = tabTitles[tabIndex];
        if (windowTitle === tabTitle)
          score = Math.max(score, 1000 + tabTitle.length);
        else if (windowTitle.includes(tabTitle))
          score = Math.max(score, 900 + tabTitle.length);
        else if (tabTitle.includes(windowTitle))
          score = Math.max(score, 800 + windowTitle.length);
      }
      for (let tokenIndex = 0; tokenIndex < hostTokens.length; ++tokenIndex) {
        if (windowTitle.includes(hostTokens[tokenIndex]))
          score = Math.max(score, 500 + hostTokens[tokenIndex].length);
      }
    }
    if (score > bestScore) {
      best = toplevel;
      bestScore = score;
    }
  }
  return best;
}
