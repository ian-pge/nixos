import QtQuick
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

// Photos and videos share a transparent full-monitor surface over the chat backdrop.
FocusScope {
  id: root
  objectName: "beeperPhotoViewer"
  required property var beeperData
  property var attachment: null
  property Item previewOrigin: null
  property bool active: true
  readonly property bool video: Format.attachmentType(attachment || {}) === "video"
  property int animationDuration: 90
  property bool closing: false
  property bool closeDelivered: false
  property bool presented: false
  property bool waitingForPreview: false
  // An h / l step replaces the photo in place instead of opening it again.
  property bool stepping: false
  property bool saving: false
  property string notice: ""
  property bool noticeFailed: false
  readonly property bool transitionRunning: transition.running
  signal closeRequested()
  signal stepRequested(int delta)

  function animateTo(target) {
    transition.stop();
    if (animationDuration <= 0) { opacity = target; return; }
    transition.from = opacity;
    transition.to = target;
    transition.start();
  }
  function syncPresentation() {
    if (!active || !visible || !attachment || width <= 0 || height <= 0) {
      transition.stop(); closing = false; presented = false; waitingForPreview = false; stepping = false; opacity = 1;
      if (!active || !visible) notice = "";
      return;
    }
    if (presented) return;
    presented = true; closing = false; closeDelivered = false;
    if (video || stepping) { stepping = false; opacity = 1; return; }
    opacity = 0;
    // Reuse decoded photos when possible; fade only once a local image is
    // ready. Downloads can immediately show their existing loading indicator.
    if (media.sourceReady && !media.downloading && !media.previewReady && !media.errorText) { waitingForPreview = true; return; }
    animateTo(1);
  }
  function revealWhenReady() {
    if (!waitingForPreview || !presented || closing || !active || !visible || !media.previewReady && !media.errorText) return;
    waitingForPreview = false;
    animateTo(1);
  }
  function requestClose() {
    if (closing || !active || !visible) return;
    // Cancel an unfinished opening immediately instead of queuing another fade.
    if (waitingForPreview || transition.running || video || !presented || animationDuration <= 0) {
      transition.stop(); waitingForPreview = false; closing = true; finishClose(); return;
    }
    closing = true;
    animateTo(0);
  }
  function finishClose() {
    if (closeDelivered) return;
    closeDelivered = true;
    closeRequested();
  }
  function refreshPresentation() { Qt.callLater(syncPresentation); Qt.callLater(syncVideoPlayback); }
  function syncVideoPlayback() {
    if (!media) return;
    if (active && visible && video) media.play();
    else media.pause();
  }
  onActiveChanged: { if (!active) syncPresentation(); else closeDelivered = false; refreshPresentation(); }
  onVisibleChanged: { if (!visible) syncPresentation(); else closeDelivered = false; refreshPresentation(); }
  onWidthChanged: Qt.callLater(syncPresentation)
  onHeightChanged: Qt.callLater(syncPresentation)
  onAttachmentChanged: {
    stepping = presented && !closing;
    closing = false; closeDelivered = false;
    transition.stop(); presented = false; waitingForPreview = false; refreshPresentation();
  }
  // d keeps a copy in the download folder; the backend never replaces a file.
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
  // Animate opacity in the render thread, with no per-frame geometry bindings.
  OpacityAnimator {
    id: transition
    target: root
    duration: root.animationDuration
    easing.type: Easing.Linear
    onFinished: if (to === 0 && root.closing && root.active && root.visible) root.finishClose()
  }
  Shortcut {
    sequence: "D"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.active && root.visible && !!root.attachment
    onActivated: root.save()
  }
  Shortcut {
    sequence: "O"; context: Qt.WindowShortcut; autoRepeat: false
    enabled: root.active && root.visible && !!root.attachment
    onActivated: root.requestClose()
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
    if (event.key !== Qt.Key_Escape) return;
    if (!event.isAutoRepeat) root.requestClose();
    event.accepted = true;
  }
  Timer { id: noticeTimer; interval: 2600; onTriggered: root.notice = "" }
  BeeperMedia {
    id: media
    objectName: "beeperFullscreenPhoto"
    anchors.fill: parent
    // The photo stays at its final size and position throughout the fade.
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
