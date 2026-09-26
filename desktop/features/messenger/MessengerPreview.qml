import QtQuick
import Quickshell

import "../../ui/Theme.js" as Theme
import "../../shell"
import "../audio"
import "../brightness"

// Local-only design preview; launched through desktop/preview.qml so all
// feature imports share the same Quickshell config root as the real shell.
ShellRoot {
  BeeperData { id: data; demo: true }
  QtObject {
    id: previewAudio
    property int volume: 50
    property real volumeStep: 0.05
    property bool volumeVisible: Quickshell.env("BEEPER_PREVIEW_VOLUME") === "1"
    property bool brightnessVisible: Quickshell.env("BEEPER_PREVIEW_BRIGHTNESS") === "1"
    property int brightness: 70
    function icon() { return "󰕾"; }
    function setVolume(delta) { volume = Math.max(0, Math.min(100, Math.round(volume + delta * 100))); }
    function showVolumeOverlay() { brightnessVisible = false; volumeVisible = true; }
    function brightnessIcon() { return "󰃠"; }
    function changeBrightness(delta) { brightness = Math.max(0, Math.min(100, brightness + delta)); }
    function showBrightnessOverlay() { volumeVisible = false; brightnessVisible = true; }
  }
  QtObject {
    id: previewBrightness
    function value(monitor) { return previewAudio.brightness; }
    function icon(monitor) { return "󰃠"; }
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 1440; implicitHeight: 1040
    title: "Messages — design preview"
    color: Theme.background
    Rectangle {
      id: content
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: "#28263d" }
        GradientStop { position: 1; color: "#101723" }
      }
      BeeperBubble {
        id: bubble; anchors.fill: parent; glassEnabled: false
        sourceWidth: center.width; sourceHeight: center.height
      }
      BeeperPanel {
        id: panel
        parent: bubble.contentItem
        anchors.fill: parent
        beeperData: data; active: bubble.expanded
        externalPhotoPreview: true
        windowFocused: content.Window.active && (activeFocus || emojiPickerOpen)
        onCloseRequested: bubble.expanded = false
      }
      MessengerPhotoWindow {
        id: photoWindow
        screen: window.screen
        visible: bubble.expanded && panel.photoPreviewOpen
        beeperData: data; attachment: panel.previewAttachment
        onVisibleChanged: if (visible) Qt.callLater(() => photoWindow.viewer.forceActiveFocus())
        onCloseRequested: { panel.closeModal(); panel.forceActiveFocus(); }
      }
      Row {
        x: 16; y: 10; spacing: 10; z: 2
        BeeperButton { text: "09:41   ·   Friday, 25 Sep"; height: 36 }
        BeeperButton {
          text: "Messages"; prominent: true; height: 36
          onClicked: { bubble.expanded = !bubble.expanded; if (bubble.expanded) panel.focusNavigation(); }
        }
      }
      Rectangle {
        id: center
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property bool overlayVisible: previewAudio.volumeVisible || previewAudio.brightnessVisible
        property real overlayReveal: overlayVisible ? 1 : 0
        y: 10; width: overlayVisible ? 280 : 434; height: 36
        z: 2; radius: 18
        color: !bubble.visible || overlayReveal > 0 ? Theme.background : "transparent"
        opacity: Math.max(bubble.originContentOpacity, overlayReveal)
        visible: opacity > 0.001
        enabled: !bubble.expanded || overlayVisible
        transform: Translate { y: bubble.visible && center.overlayReveal === 0 ? bubble.surfaceItem.y - center.y : 0 }
        Behavior on overlayReveal { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
        Row {
          anchors.centerIn: parent; spacing: 25
          visible: !center.overlayVisible && bubble.originContentOpacity > 0
          Repeater {
            model: 8
            Text { required property int index; text: index + 1; color: index === 0 ? Theme.action : Theme.secondary; font { family: "Ubuntu Nerd Font"; pixelSize: 16; bold: true } }
          }
        }
        VolumeIndicator {
          anchors.fill: parent; controller: previewAudio; visible: previewAudio.volumeVisible
          onAdjustRequested: delta => { previewAudio.setVolume(delta); previewAudio.showVolumeOverlay(); }
        }
        BrightnessIndicator {
          anchors.fill: parent; controller: previewBrightness; visible: previewAudio.brightnessVisible
          onChangeRequested: delta => { previewAudio.changeBrightness(delta); previewAudio.showBrightnessOverlay(); }
        }
      }
      Row {
        anchors.right: parent.right; anchors.rightMargin: 16
        y: 10; spacing: 6; z: 2
        BeeperButton { text: "−"; height: 36; onClicked: { previewAudio.setVolume(-0.05); previewAudio.showVolumeOverlay(); } }
        BeeperButton { text: "󰕾  " + previewAudio.volume + "%"; height: 36; onClicked: previewAudio.volumeVisible = !previewAudio.volumeVisible }
        BeeperButton { text: "+"; height: 36; onClicked: { previewAudio.setVolume(0.05); previewAudio.showVolumeOverlay(); } }
      }
    }
    Timer {
      interval: 150; running: true
      onTriggered: {
        if (Quickshell.env("BEEPER_PREVIEW_ARCHIVES") === "1") {
          data.chats = data.chats.map(chat => chat.id === "design" ? Object.assign({}, chat, {isArchived: true}) : chat);
          data.showArchived = true;
        }
        if (Quickshell.env("BEEPER_PREVIEW_MEDIA") === "1") {
          data.demoMessages.studio = data.demoMessages.studio.concat([{id: "preview-audio", chatID: "studio", senderName: "Noé", timestamp: new Date().toISOString(),
            attachments: [{type: "audio", isVoiceNote: true, duration: 34,
              previewWaveform: [0.2,0.45,0.8,0.62,0.94,0.4,0.75,0.55,0.9,0.3,0.45,0.7,0.9,0.85,0.6,0.2,0.18,0.6,0.85,0.45,0.65,0.95,0.8,0.5,0.35,0.7,0.85,0.6,0.98,0.55,0.42,0.7,0.5,0.65,0.25,0.1]}]}]);
          data.loadMessages(false);
        }
        const connection = Quickshell.env("BEEPER_PREVIEW_CONNECTION") || "";
        if (["offline", "needs-token", "keyring-unavailable"].includes(connection)) {
          data.clearSelection(); data.chats = []; data.state = connection;
          data.statusMessage = connection === "offline" ? "Reconnecting automatically with your saved token…" : "";
        }
        const stage = Quickshell.env("BEEPER_PREVIEW_PROGRESS") || "";
        if (stage !== "") {
          bubble.animate = false;
          bubble.expanded = true;
          bubble.progress = Math.max(0, Math.min(1, Number(stage)));
        } else bubble.expanded = true;
        panel.focusNavigation();
        if (Quickshell.env("BEEPER_PREVIEW_SEARCH") === "1") panel.openChatSearch();
        const messageQuery = Quickshell.env("BEEPER_PREVIEW_MESSAGE_SEARCH") || "";
        if (messageQuery) panel.openConversationSearch(messageQuery);
      }
    }
    Timer {
      interval: 800; running: !!Quickshell.env("BEEPER_PREVIEW_MESSAGE_SEARCH")
      onTriggered: panel.acceptConversationSearch()
    }
    Timer {
      interval: 1200; running: !!Quickshell.env("BEEPER_PREVIEW_SCREENSHOT"); repeat: false
      onTriggered: {
        console.log("Messenger preview:", JSON.stringify({expanded: bubble.expanded, progress: bubble.progress,
          visible: bubble.visible, enabled: bubble.enabled, animating: bubble.animating,
          width: content.width, height: content.height, panelWidth: bubble.panelWidth, panelHeight: bubble.panelHeight}));
        content.grabToImage(result => {
          if (!result.saveToFile(Quickshell.env("BEEPER_PREVIEW_SCREENSHOT"))) Qt.exit(1);
          else Qt.quit();
        });
      }
    }
  }
}
