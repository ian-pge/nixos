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
