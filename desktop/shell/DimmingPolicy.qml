import QtQuick

// One per-monitor decision; native special workspaces keep their compositor
// backdrop below their windows, rather than receiving a second shell overlay.
QtObject {
  property string centralMode: "workspaces"
  property bool chatOpen: false
  property bool specialWorkspaceOpen: false
  property bool opaqueTheme: true

  readonly property bool centralRequestsDimming:
    !["workspaces", "volume", "brightness", "notification", "dictation", "media"].includes(centralMode)
  readonly property bool requested: specialWorkspaceOpen || chatOpen || centralRequestsDimming
  readonly property bool compositorOwnsBackdrop: specialWorkspaceOpen
  readonly property bool shellSuppressed: !opaqueTheme || compositorOwnsBackdrop
  readonly property bool shellBackdropWanted: requested && !shellSuppressed
}
