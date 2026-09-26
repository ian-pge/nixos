import QtQuick
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

// Photos and videos share the same full-monitor surface and backdrop blur.
FocusScope {
  id: root
  objectName: "beeperPhotoViewer"
  required property var beeperData
  property var attachment: null
  property bool active: true
  readonly property bool video: Format.attachmentType(attachment || {}) === "video"
  signal closeRequested()
  function syncVideoPlayback() {
    if (!media) return;
    if (active && visible && video) media.play();
    else media.pause();
  }
  onActiveChanged: Qt.callLater(syncVideoPlayback)
  onVisibleChanged: Qt.callLater(syncVideoPlayback)
  onAttachmentChanged: Qt.callLater(syncVideoPlayback)
  Component.onCompleted: Qt.callLater(syncVideoPlayback)
  Shortcut {
    sequence: "Space"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.active && root.visible && root.video
    onActivated: media.togglePlayback()
  }
  Shortcut {
    sequence: "H"; context: Qt.WindowShortcut
    enabled: root.active && root.visible && root.video
    onActivated: media.seek(-5000)
  }
  Shortcut {
    sequence: "L"; context: Qt.WindowShortcut
    enabled: root.active && root.visible && root.video
    onActivated: media.seek(5000)
  }
  Keys.onPressed: event => {
    if (event.key !== Qt.Key_Escape && !(event.key === Qt.Key_Space && !root.video)) return;
    if (!event.isAutoRepeat) root.closeRequested();
    event.accepted = true;
  }
  Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.background, 0.28) }
  BeeperMedia {
    id: media
    objectName: "beeperFullscreenPhoto"
    anchors.fill: parent
    attachment: root.attachment || {}
    beeperData: root.beeperData
    expanded: true
    playbackEnabled: root.active && root.visible
    renderEnabled: root.active && root.visible
    onPreviewRequested: root.closeRequested()
  }
}
