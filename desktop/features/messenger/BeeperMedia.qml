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
  property string audioKey: ""
  readonly property string kind: Format.attachmentType(attachment)
  readonly property var sharedAudio: kind === "audio" ? beeperData?.audioPlayback || null : null
  readonly property string effectiveAudioKey: audioKey || JSON.stringify(["attachment", attachment.id || attachment.path || Format.attachmentSource(attachment)])
  readonly property bool currentAudio: sharedAudio !== null && sharedAudio.key === effectiveAudioKey
  readonly property bool mediaDownloading: currentAudio ? sharedAudio.downloading : downloading
  readonly property string mediaError: currentAudio ? sharedAudio.errorText : errorText
  property string sourceUrl: Format.attachmentSource(attachment)
  property bool downloading: false
  property int resolutionGeneration: 0
  property bool inlinePlayWhenReady: false
  readonly property bool playWhenReady: sharedAudio ? currentAudio && sharedAudio.playWhenReady : inlinePlayWhenReady
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
    mediaDownloading || mediaError ? statusColumn.implicitHeight : 0)
  clip: true

  function validSize(width, height) { return typeof width === "number" && typeof height === "number" && isFinite(width) && isFinite(height) && width > 0 && height > 0; }
  function rememberSize(width, height) {
    if (!validSize(width, height)) return;
    decodedSize = Qt.size(width, height);
    decodedSource = sourceUrl;
  }
  function playPendingMedia() {
    if (sharedAudio) return;
    if (!playWhenReady || !playbackEnabled || !renderEnabled || !visible || downloading || errorText || !sourceReady || !mediaLoader?.item) return;
    mediaLoader.item.play();
  }
  function play() {
    if (sharedAudio) { sharedAudio.play(effectiveAudioKey, attachment); return; }
    if ((kind !== "audio" && kind !== "video") || !playbackEnabled || !renderEnabled || !visible || errorText) return;
    if (playWhenReady || mediaLoader?.item?.playing) return;
    inlinePlayWhenReady = true;
    resolveIfNeeded(); playPendingMedia();
  }
  function pause() {
    if (sharedAudio) { if (currentAudio) sharedAudio.pause(); return; }
    pauseInline();
  }
  function pauseInline() {
    if (sharedAudio) return;
    inlinePlayWhenReady = false;
    if (mediaLoader?.item) mediaLoader.item.stop();
  }
  function togglePlayback() {
    if ((kind !== "audio" && kind !== "video") || !playbackEnabled || !renderEnabled || !visible) return;
    if (sharedAudio) { sharedAudio.toggle(effectiveAudioKey, attachment); return; }
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
      if (error || !result || result.error) { inlinePlayWhenReady = false; errorText = error ? error.message : result?.error || "Preview unavailable"; return; }
      sourceUrl = result.srcURL || "";
      Qt.callLater(playPendingMedia);
    });
  }
  onPlaybackEnabledChanged: {
    if (!playbackEnabled) pauseInline();
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
  onRenderEnabledChanged: if (renderEnabled) { resolveIfNeeded(); requestWaveform(); } else pauseInline()
  function resolveIfNeeded() { if (!sharedAudio && visible && playbackEnabled && renderEnabled && sourceUrl && !sourceReady) resolve(); }
  onVisibleChanged: { if (!visible) pauseInline(); else { resolveIfNeeded(); requestWaveform(); } }
  onAttachmentChanged: { ++resolutionGeneration; downloading = false; pauseInline(); sourceUrl = Format.attachmentSource(attachment); errorText = ""; resolveIfNeeded(); }
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
    visible: !root.mediaDownloading && !root.mediaError
    active: root.renderEnabled && (root.kind === "audio" || root.kind === "video")
    onLoaded: root.playPendingMedia()
    sourceComponent: root.sharedAudio ? sharedAudioComponent : inlineMediaComponent
  }
  Component {
    id: sharedAudioComponent
    Item {
      property alias player: audioControls
      readonly property bool playing: root.currentAudio && root.sharedAudio.active
      QtObject {
        id: audioControls
        objectName: "beeperMediaPlayer"
        readonly property var audioOutput: root.sharedAudio?.player.audioOutput || null
        readonly property int playbackState: root.currentAudio ? root.sharedAudio.player.playbackState : MediaPlayer.StoppedState
        readonly property real duration: root.currentAudio ? root.sharedAudio.player.duration : 0
        readonly property real position: root.currentAudio ? root.sharedAudio.player.position : 0
        readonly property real playbackRate: root.currentAudio ? root.sharedAudio.player.playbackRate : 1
        readonly property bool seekable: root.currentAudio && root.sharedAudio.player.seekable
        function play() { root.play(); }
        function pause() { root.pause(); }
        function setPosition(value) { if (root.currentAudio) root.sharedAudio.player.setPosition(value); }
        function setPlaybackRate(value) { if (root.currentAudio) root.sharedAudio.player.playbackRate = value; }
      }
      BeeperPlaybackControls {
        anchors.fill: parent
        player: audioControls
        accent: root.accent; accentBackground: root.accentBackground
        enabled: root.playbackEnabled
        fallbackDuration: (root.attachment.duration || 0) * 1000
        peaks: root.waveformPeaks
      }
    }
  }
  Component {
    id: inlineMediaComponent
    Item {
      property alias player: mediaPlayer
      readonly property bool playing: mediaPlayer.playbackState === MediaPlayer.PlayingState
      function play() { mediaPlayer.play(); }
      function stop() { mediaPlayer.pause(); }
      MediaPlayer {
        id: mediaPlayer
        objectName: "beeperMediaPlayer"
        // Loading a source already starts decoding even without autoPlay.
        // Inactive monitor panels and hidden previews must not create decoders.
        // Persistent voice playback is owned separately by BeeperAudioPlayback.
        source: root.playbackEnabled && root.visible && root.sourceReady && !root.downloading ? root.sourceUrl : ""
        audioOutput: AudioOutput {}
        videoOutput: video
        loops: root.attachment.isGif ? MediaPlayer.Infinite : 1
        autoPlay: !!root.attachment.isGif && !root.expanded && root.playbackEnabled && root.visible
        onPlaybackStateChanged: if (playbackState === MediaPlayer.PlayingState) root.inlinePlayWhenReady = false
        onErrorOccurred: (error, errorString) => { root.inlinePlayWhenReady = false; root.errorText = errorString; }
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
    anchors.fill: parent; visible: root.mediaDownloading || !!root.mediaError
    color: "transparent"
    Column {
      id: statusColumn
      anchors.centerIn: parent; width: parent.width - 20; spacing: 5
      Text { width: parent.width; text: root.mediaDownloading ? "Loading…" : root.mediaError; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: root.accentBackground ? Theme.background : Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      BeeperButton { anchors.horizontalCenter: parent.horizontalCenter; visible: !root.mediaDownloading; text: "Retry"; prominent: root.accentBackground; accent: root.accent; onClicked: { if (root.sharedAudio) root.play(); else { root.errorText = ""; root.resolve(); } } }
    }
  }
}
