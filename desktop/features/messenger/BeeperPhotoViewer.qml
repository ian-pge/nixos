import QtQuick
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

// Photos and videos share the same full-monitor surface and dimmed backdrop.
FocusScope {
  id: root
  objectName: "beeperPhotoViewer"
  required property var beeperData
  property var attachment: null
  property Item previewOrigin: null
  property bool active: true
  readonly property bool video: Format.attachmentType(attachment || {}) === "video"
  property int animationDuration: 180
  property real progress: 1
  property bool closing: false
  property bool presented: false
  property bool waitingForPreview: false
  property bool sharedOrigin: false
  property rect originRect: Qt.rect(0, 0, 0, 0)
  property real originScale: 1
  property real originOffsetX: 0
  property real originOffsetY: 0
  property real closeFadeStart: -1
  // An h / l step replaces the photo in place instead of opening it again.
  property bool stepping: false
  property bool saving: false
  property string notice: ""
  property bool noticeFailed: false
  readonly property bool transitionRunning: transition.running
  readonly property real imageScale: sharedOrigin ? originScale + (1 - originScale) * progress : 1
  readonly property real imageOffsetX: sharedOrigin ? originOffsetX * (1 - progress) : 0
  readonly property real imageOffsetY: sharedOrigin ? originOffsetY * (1 - progress) : 0
  signal closeRequested()
  signal stepRequested(int delta)

  // mapToItem also handles the separate fullscreen Wayland surface. Reject
  // missing, recycled or clipped thumbnails instead of flying off the screen.
  function mappedOrigin() {
    const item = previewOrigin;
    if (!item || !item.visible || item.width <= 0 || item.height <= 0 || item.opacity <= 0
        || item.renderEnabled === false || item.previewReady === false) return null;
    if (item.attachment) {
      if (item.attachment.id && attachment?.id && item.attachment.id !== attachment.id) return null;
      const source = Format.attachmentSource(attachment || {});
      if (Format.attachmentSource(item.attachment) !== source && (!item.sourceReady || item.sourceUrl !== source)) return null;
    }
    const rect = item.previewRect || Qt.rect(0, 0, item.width, item.height);
    if (rect.width <= 0 || rect.height <= 0) return null;
    for (let ancestor = item.parent; ancestor; ancestor = ancestor.parent) {
      if (!ancestor.visible || ancestor.opacity <= 0) return null;
      if (!ancestor.clip) continue;
      const a = item.mapToItem(ancestor, rect.x, rect.y);
      const b = item.mapToItem(ancestor, rect.x + rect.width, rect.y + rect.height);
      if (a.x < -1 || a.y < -1 || b.x > ancestor.width + 1 || b.y > ancestor.height + 1) return null;
    }
    const a = item.mapToItem(root, rect.x, rect.y);
    const b = item.mapToItem(root, rect.x + rect.width, rect.y + rect.height);
    if (![a.x, a.y, b.x, b.y].every(Number.isFinite) || a.x < -1 || a.y < -1
        || b.x > width + 1 || b.y > height + 1 || b.x <= a.x || b.y <= a.y) return null;
    return Qt.rect(a.x, a.y, b.x - a.x, b.y - a.y);
  }
  function setOrigin(rect) {
    sharedOrigin = !!rect;
    if (!rect) return;
    originRect = rect;
    const ratio = rect.width / rect.height;
    const fittedWidth = Math.min(width, height * ratio);
    originScale = Math.min(1, rect.width / Math.max(1, fittedWidth));
    originOffsetX = rect.x + rect.width / 2 - width / 2;
    originOffsetY = rect.y + rect.height / 2 - height / 2;
  }
  function animateTo(target) {
    transition.stop();
    transition.to = target;
    transition.duration = Math.max(1, animationDuration * Math.abs(target - progress));
    transition.start();
  }
  function syncPresentation() {
    if (!active || !visible || !attachment || width <= 0 || height <= 0) {
      transition.stop(); closing = false; presented = false; waitingForPreview = false; stepping = false; progress = 1;
      if (!active || !visible) notice = "";
      return;
    }
    if (presented) return;
    presented = true; closing = false; closeFadeStart = -1;
    if (video || stepping) { stepping = false; sharedOrigin = false; progress = 1; return; }
    setOrigin(media.errorText ? null : mappedOrigin());
    progress = 0;
    // Decoding stays asynchronous. Start the short visual traversal only when
    // the fullscreen image can actually paint it, not during a blank load.
    if (sharedOrigin && !media.previewReady && !media.errorText) { waitingForPreview = true; return; }
    animateTo(1);
  }
  function revealWhenReady() {
    if (!waitingForPreview || !presented || closing || !active || !visible || !media.previewReady && !media.errorText) return;
    waitingForPreview = false;
    setOrigin(media.errorText ? null : mappedOrigin());
    animateTo(1);
  }
  function requestClose() {
    if (closing || !active || !visible) return;
    if (waitingForPreview) { waitingForPreview = false; closing = true; closeRequested(); return; }
    if (video || !presented || animationDuration <= 0) { closeRequested(); return; }
    // Keep the original trajectory when reversing an opening. At rest, use
    // the thumbnail's current position only if it still matches the source.
    const destination = mappedOrigin();
    if (!transition.running) setOrigin(destination);
    else if (!destination || Math.abs(destination.x - originRect.x) > 1 || Math.abs(destination.y - originRect.y) > 1
             || Math.abs(destination.width - originRect.width) > 1 || Math.abs(destination.height - originRect.height) > 1)
      closeFadeStart = Math.max(0.001, progress);
    closing = true;
    animateTo(0);
  }
  function refreshPresentation() { Qt.callLater(syncPresentation); Qt.callLater(syncVideoPlayback); }
  function syncVideoPlayback() {
    if (!media) return;
    if (active && visible && video) media.play();
    else media.pause();
  }
  onActiveChanged: { if (!active) syncPresentation(); refreshPresentation(); }
  onVisibleChanged: { if (!visible) syncPresentation(); refreshPresentation(); }
  onWidthChanged: Qt.callLater(syncPresentation)
  onHeightChanged: Qt.callLater(syncPresentation)
  onAttachmentChanged: {
    stepping = presented && !closing;
    transition.stop(); presented = false; closing = false; waitingForPreview = false; refreshPresentation();
  }
  // Enter keeps a copy in the download folder; the backend never replaces a file.
  function save() {
    if (!active || !visible || !attachment || saving) return;
    saving = true; notice = "Saving…"; noticeFailed = false; noticeTimer.stop();
    const source = media.sourceReady ? media.sourceUrl : Format.attachmentSource(attachment);
    beeperData.request("saveAttachment", {url: source, fileName: attachment.fileName || "", mimeType: attachment.mimeType || ""}, (result, error) => {
      saving = false;
      noticeFailed = !!error || !result?.path;
      notice = noticeFailed ? error?.message || "Could not save this file."
        : "Saved to " + result.path.split("/").slice(-2, -1)[0] + " · " + result.name;
      noticeTimer.restart();
    });
  }
  Component.onCompleted: refreshPresentation()
  NumberAnimation {
    id: transition
    target: root; property: "progress"
    easing.type: Easing.OutCubic
    onFinished: if (root.closing && root.active && root.visible) root.closeRequested()
  }
  Shortcut {
    sequence: "Space"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.active && root.visible && root.video
    onActivated: media.togglePlayback()
  }
  Shortcut {
    sequence: "H"; context: Qt.WindowShortcut
    enabled: root.active && root.visible && !!root.attachment
    onActivated: root.video ? media.seek(-5000) : root.stepRequested(-1)
  }
  Shortcut {
    sequence: "L"; context: Qt.WindowShortcut
    enabled: root.active && root.visible && !!root.attachment
    onActivated: root.video ? media.seek(5000) : root.stepRequested(1)
  }
  Keys.onPressed: event => {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (!event.isAutoRepeat) root.save();
      event.accepted = true;
      return;
    }
    if (event.key !== Qt.Key_Escape && !(event.key === Qt.Key_Space && !root.video)) return;
    if (!event.isAutoRepeat) root.requestClose();
    event.accepted = true;
  }
  Timer { id: noticeTimer; interval: 2600; onTriggered: root.notice = "" }
  Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.background, 0.28); opacity: root.progress }
  BeeperMedia {
    id: media
    objectName: "beeperFullscreenPhoto"
    anchors.fill: parent
    // Fixed decoded image and final geometry: each frame only transforms the
    // scene graph node, including when Escape reverses an unfinished opening.
    scale: root.imageScale
    transform: Translate { x: root.imageOffsetX; y: root.imageOffsetY }
    opacity: !root.sharedOrigin ? root.progress
      : root.closing && root.closeFadeStart >= 0 ? Math.min(1, root.progress / root.closeFadeStart) : 1
    attachment: root.attachment || {}
    beeperData: root.beeperData
    expanded: true
    playbackEnabled: root.active && root.visible
    renderEnabled: root.active && root.visible
    onPreviewReadyChanged: Qt.callLater(root.revealWhenReady)
    onErrorTextChanged: Qt.callLater(root.revealWhenReady)
    onPreviewRequested: root.requestClose()
  }
  Rectangle {
    objectName: "beeperViewerNotice"
    anchors.horizontalCenter: parent.horizontalCenter
    y: 32
    width: noticeLabel.implicitWidth + 40; height: 40; radius: 20
    color: Theme.surface
    visible: root.notice !== ""
    Text {
      id: noticeLabel
      objectName: "beeperViewerNoticeText"
      anchors.centerIn: parent
      text: root.notice
      color: root.noticeFailed ? Theme.error : Theme.foreground
      font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
    }
  }
}
