import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import "Theme.js" as Theme
import "BeeperFormat.js" as Format

Rectangle {
  id: root
  required property var attachment
  property var beeperData: null
  property bool expanded: false
  property bool playbackEnabled: true
  readonly property string kind: Format.attachmentType(attachment)
  property string sourceUrl: Format.attachmentSource(attachment)
  property bool downloading: false
  property string errorText: ""
  readonly property bool visual: kind === "image" || kind === "gif" || kind === "video"
  signal previewRequested(var attachment)
  implicitHeight: visual ? (expanded ? 430 : Math.min(250, width * 0.62)) : 88
  radius: 12
  color: Qt.alpha(Theme.background, 0.48)
  clip: true

  function resolve() {
    if (!beeperData || downloading || !visible || !playbackEnabled) return;
    const url = attachment.srcURL || attachment.url || attachment.id || "";
    if (!url) return;
    downloading = true;
    beeperData.request("download", {url: url}, (result, error) => {
      downloading = false;
      if (error || result.error) { errorText = error ? error.message : result.error; return; }
      sourceUrl = result.srcURL || "";
    });
  }
  onPlaybackEnabledChanged: if (!playbackEnabled && mediaLoader.item) mediaLoader.item.stop()
  function resolveIfNeeded() { if (visible && playbackEnabled && sourceUrl && !/^(file:|https?:|data:)/.test(sourceUrl)) resolve(); }
  onVisibleChanged: resolveIfNeeded()
  onAttachmentChanged: { sourceUrl = Format.attachmentSource(attachment); errorText = ""; resolveIfNeeded(); }
  Component.onCompleted: resolveIfNeeded()

  Loader {
    anchors.fill: parent
    active: root.kind === "image" || root.kind === "gif"
    sourceComponent: AnimatedImage {
      source: root.sourceUrl
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      playing: root.playbackEnabled
      cache: false
      onStatusChanged: if (status === Image.Error) root.errorText = "Aperçu indisponible"
      MouseArea { anchors.fill: parent; onClicked: root.previewRequested(root.attachment) }
    }
  }
  Loader {
    id: mediaLoader
    anchors.fill: parent
    active: root.kind === "audio" || root.kind === "video"
    sourceComponent: Item {
      function stop() { player.pause(); }
      MediaPlayer {
        id: player
        source: root.sourceUrl
        audioOutput: AudioOutput {}
        videoOutput: video
        loops: root.attachment.isGif ? MediaPlayer.Infinite : 1
        autoPlay: !!root.attachment.isGif && root.playbackEnabled && root.visible
        onErrorOccurred: root.errorText = errorString
      }
      VideoOutput { id: video; anchors.fill: parent; visible: root.kind === "video" }
      Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 80; color: root.kind === "video" ? Qt.alpha(Theme.background, 0.86) : "transparent"
        RowLayout {
          anchors { fill: parent; margins: 10 }
          spacing: 8
          BeeperButton { text: player.playbackState === MediaPlayer.PlayingState ? "Ⅱ" : "▶"; prominent: true; enabled: root.playbackEnabled; onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
          ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            Text { text: root.kind === "audio" ? "Message audio" : "Vidéo"; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
            Slider {
              Layout.fillWidth: true; Layout.preferredHeight: 24; from: 0; to: Math.max(1, player.duration); value: player.position; onMoved: player.setPosition(value)
              Keys.onPressed: event => {
                if (event.key === Qt.Key_H || event.key === Qt.Key_L) { player.setPosition(Math.max(0, Math.min(player.duration, player.position + (event.key === Qt.Key_H ? -5000 : 5000)))); event.accepted = true; }
              }
            }
          }
          Text { text: Format.duration(player.position || player.duration); color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
          BeeperButton { text: player.playbackRate + "×"; onClicked: player.playbackRate = player.playbackRate >= 2 ? 1 : player.playbackRate + 0.5 }
        }
      }
    }
  }
  RowLayout {
    visible: root.kind === "file"
    anchors { fill: parent; margins: 14 }
    Text { text: "󰈙"; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.icon } color: Theme.sideApplications }
    ColumnLayout {
      Layout.fillWidth: true
      Text { Layout.fillWidth: true; text: root.attachment.fileName || "Pièce jointe"; elide: Text.ElideMiddle; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control } }
      Text { text: Format.bytes(root.attachment.fileSize || root.attachment.size); color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
    }
    BeeperButton { text: "Ouvrir"; onClicked: {
      if (root.sourceUrl.startsWith("file:")) Qt.openUrlExternally(root.sourceUrl);
      else root.resolve();
    } }
  }
  Rectangle {
    anchors.fill: parent; visible: root.downloading || !!root.errorText
    color: Qt.alpha(Theme.background, 0.92)
    Column {
      anchors.centerIn: parent; width: parent.width - 20; spacing: 5
      Text { width: parent.width; text: root.downloading ? "Chargement…" : root.errorText; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      BeeperButton { anchors.horizontalCenter: parent.horizontalCenter; visible: !root.downloading; text: "Télécharger"; onClicked: { root.errorText = ""; root.resolve(); } }
    }
  }
}
