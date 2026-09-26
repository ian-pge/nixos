import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Item {
  id: root
  objectName: "beeperMedia"
  required property var attachment
  property var beeperData: null
  property bool expanded: false
  property bool playbackEnabled: true
  property bool renderEnabled: true
  property color accent: Theme.sideApplications
  property bool accentBackground: false
  readonly property string kind: Format.attachmentType(attachment)
  property string sourceUrl: Format.attachmentSource(attachment)
  property bool downloading: false
  property int resolutionGeneration: 0
  property bool playWhenReady: false
  property string errorText: ""
  readonly property bool sourceReady: /^(file:|https?:|data:)/.test(sourceUrl)
  readonly property var waveformPeaks: beeperData?.demo ? attachment.previewWaveform || []
    : beeperData?.waveforms?.[JSON.stringify(sourceUrl)]?.peaks || []
  readonly property bool visual: kind === "image" || kind === "gif" || kind === "video"
  readonly property real maximumVisualHeight: expanded ? 430 : 250
  // Public attachment.size is available before decoding. Keep the decoded size
  // after unloading an offscreen player/image so scrolling cannot resize rows.
  property size decodedSize: Qt.size(0, 0)
  property string decodedSource: ""
  readonly property size naturalSize: {
    if (decodedSource === sourceUrl && decodedSize.width > 0 && decodedSize.height > 0) return decodedSize;
    const size = attachment.size;
    return validSize(size?.width, size?.height) ? Qt.size(size.width, size.height) : Qt.size(400, 250);
  }
  readonly property real aspectRatio: naturalSize.width / naturalSize.height
  implicitWidth: visual ? Math.max(kind === "video" ? 240 : 0, Math.min(naturalSize.width, maximumVisualHeight * aspectRatio))
    : kind === "audio" ? 392 : fileRow.implicitWidth
  signal previewRequested(var attachment)
  implicitHeight: Math.max(visual ? Math.min(maximumVisualHeight, naturalSize.height, width / aspectRatio) : kind === "audio" ? 48 : 64,
    downloading || errorText ? statusColumn.implicitHeight : 0)
  clip: true

  function validSize(width, height) { return typeof width === "number" && typeof height === "number" && isFinite(width) && isFinite(height) && width > 0 && height > 0; }
  function rememberSize(width, height) {
    if (!validSize(width, height)) return;
    decodedSize = Qt.size(width, height);
    decodedSource = sourceUrl;
  }
  function playPendingMedia() {
    if (!playWhenReady || !playbackEnabled || !renderEnabled || !visible || downloading || errorText || !sourceReady || !mediaLoader?.item) return;
    mediaLoader.item.play();
  }
  function play() {
    if ((kind !== "audio" && kind !== "video") || !playbackEnabled || !renderEnabled || !visible || errorText) return;
    if (playWhenReady || mediaLoader?.item?.playing) return;
    playWhenReady = true;
    resolveIfNeeded(); playPendingMedia();
  }
  function pause() {
    playWhenReady = false;
    if (mediaLoader?.item) mediaLoader.item.stop();
  }
  function togglePlayback() {
    if ((kind !== "audio" && kind !== "video") || !playbackEnabled || !renderEnabled || !visible) return;
    if (playWhenReady || mediaLoader?.item?.playing) pause();
    else play();
  }
  function seek(delta) {
    const player = mediaLoader?.item?.player;
    if (!playbackEnabled || !renderEnabled || !visible || !player?.seekable || player.duration <= 0) return;
    player.setPosition(Math.max(0, Math.min(player.duration, player.position + delta)));
  }
  function resolve() {
    if (!beeperData || downloading || !visible || !playbackEnabled || !renderEnabled) return;
    const url = attachment.srcURL || attachment.url || attachment.id || "";
    if (!url) return;
    const generation = resolutionGeneration;
    downloading = true;
    beeperData.request("download", {url: url}, (result, error) => {
      if (generation !== resolutionGeneration) return;
      downloading = false;
      if (error || !result || result.error) { playWhenReady = false; errorText = error ? error.message : result?.error || "Preview unavailable"; return; }
      sourceUrl = result.srcURL || "";
      Qt.callLater(playPendingMedia);
    });
  }
  onPlaybackEnabledChanged: {
    if (!playbackEnabled) pause();
    else { resolveIfNeeded(); requestWaveform(); }
  }
  function requestWaveform() {
    if (kind === "audio" && visible && playbackEnabled && renderEnabled && !downloading && !errorText && sourceUrl) beeperData?.ensureWaveform(sourceUrl);
  }
  onSourceUrlChanged: { Qt.callLater(requestWaveform); Qt.callLater(playPendingMedia); }
  Connections {
    target: root.beeperData
    function onConnectedChanged() { Qt.callLater(root.requestWaveform); }
  }
  onRenderEnabledChanged: if (renderEnabled) { resolveIfNeeded(); requestWaveform(); } else pause()
  function resolveIfNeeded() { if (visible && playbackEnabled && renderEnabled && sourceUrl && !sourceReady) resolve(); }
  onVisibleChanged: { if (!visible) pause(); else { resolveIfNeeded(); requestWaveform(); } }
  onAttachmentChanged: { ++resolutionGeneration; downloading = false; pause(); sourceUrl = Format.attachmentSource(attachment); errorText = ""; resolveIfNeeded(); }
  Component.onCompleted: { resolveIfNeeded(); requestWaveform(); }

  Loader {
    anchors.fill: parent
    visible: !root.downloading && !root.errorText
    active: root.renderEnabled && (root.kind === "image" || root.kind === "gif")
    sourceComponent: AnimatedImage {
      objectName: "beeperMediaImage"
      source: root.sourceReady && !root.downloading ? root.sourceUrl : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      playing: root.playbackEnabled
      cache: false
      onStatusChanged: {
        if (status === Image.Error) root.errorText = "Preview unavailable";
        else if (status === Image.Ready) root.rememberSize(implicitWidth, implicitHeight);
      }
      MouseArea { anchors.fill: parent; onClicked: root.previewRequested(root.attachment) }
    }
  }
  Loader {
    id: mediaLoader
    anchors.fill: parent
    visible: !root.downloading && !root.errorText
    active: root.renderEnabled && (root.kind === "audio" || root.kind === "video")
    onLoaded: root.playPendingMedia()
    sourceComponent: Item {
      property alias player: mediaPlayer
      readonly property bool playing: mediaPlayer.playbackState === MediaPlayer.PlayingState
      function play() { mediaPlayer.play(); }
      function stop() { mediaPlayer.pause(); }
      MediaPlayer {
        id: mediaPlayer
        objectName: "beeperMediaPlayer"
        source: root.sourceReady && !root.downloading ? root.sourceUrl : ""
        audioOutput: AudioOutput {}
        videoOutput: video
        loops: root.attachment.isGif ? MediaPlayer.Infinite : 1
        autoPlay: !!root.attachment.isGif && !root.expanded && root.playbackEnabled && root.visible
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) root.playWhenReady = false
        onErrorOccurred: (error, errorString) => { root.playWhenReady = false; root.errorText = errorString; }
      }
      VideoOutput {
        id: video; anchors.fill: parent; visible: root.kind === "video"
        objectName: "beeperMediaVideo"
        fillMode: VideoOutput.PreserveAspectFit
        onSourceRectChanged: root.rememberSize(sourceRect.width, sourceRect.height)
      }
      Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.kind === "video" ? 60 : parent.height
        Rectangle {
          anchors.fill: parent; visible: root.kind === "video"
          gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Qt.alpha(Theme.background, 0.9) }
          }
        }
        BeeperPlaybackControls {
          anchors { fill: parent; leftMargin: root.kind === "video" ? 10 : 0; rightMargin: root.kind === "video" ? 10 : 0 }
          player: mediaPlayer
          accent: root.accentBackground && root.kind === "video" ? Theme.sideApplications : root.accent
          accentBackground: root.accentBackground && root.kind === "audio"
          enabled: root.playbackEnabled
          // Beeper attachment durations are seconds; Qt Multimedia uses ms.
          fallbackDuration: (root.attachment.duration || 0) * 1000
          peaks: root.kind === "audio" ? root.waveformPeaks : []
        }
      }
    }
  }
  RowLayout {
    id: fileRow
    visible: root.kind === "file" && !root.downloading && !root.errorText
    anchors.fill: parent
    Text { text: "󰈙"; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.icon } color: root.accentBackground ? Theme.background : Theme.sideApplications }
    ColumnLayout {
      Layout.fillWidth: true
      Text { Layout.fillWidth: true; text: root.attachment.fileName || "Attachment"; elide: Text.ElideMiddle; color: root.accentBackground ? Theme.background : Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control } }
      Text { text: Format.bytes(root.attachment.fileSize || root.attachment.size); color: root.accentBackground ? Theme.background : Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
    }
    BeeperButton { text: "Open"; prominent: root.accentBackground; accent: root.accent; onClicked: {
      if (root.sourceUrl.startsWith("file:")) Qt.openUrlExternally(root.sourceUrl);
      else root.resolve();
    } }
  }
  Rectangle {
    anchors.fill: parent; visible: root.downloading || !!root.errorText
    color: "transparent"
    Column {
      id: statusColumn
      anchors.centerIn: parent; width: parent.width - 20; spacing: 5
      Text { width: parent.width; text: root.downloading ? "Loading…" : root.errorText; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: root.accentBackground ? Theme.background : Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      BeeperButton { anchors.horizontalCenter: parent.horizontalCenter; visible: !root.downloading; text: "Retry"; prominent: root.accentBackground; accent: root.accent; onClicked: { root.errorText = ""; root.resolve(); } }
    }
  }
}
