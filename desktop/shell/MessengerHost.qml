import QtQuick
import Quickshell.Hyprland
import "../features/messenger"
import "../ui/Theme.js" as Theme

// Per-monitor shell adapter: shared layer-surface focus, placement, animation
// and dictation feedback. Notifications always belong to the top bar.
Item {
  id: root
  required property var controller
  required property var panelWindow
  required property string monitorName
  property bool windowFocused: false
  property bool keyboardSelectorActive: false
  property bool dictating: false
  property bool transcribing: false
  property real barTop: 10
  property real workAreaTop: 46
  property real sourceWidth: 434
  property real sourceHeight: 36
  property bool nativeDialogOpen: false
  readonly property bool active: controller.visible && monitorName === controller.targetMonitor
  readonly property bool presented: bubble.visible
  // Keep the chat keyboard-capable while its fullscreen media owns focus.
  // The compositor can then return to this surface as the photo unmaps.
  readonly property bool wantsKeyboard: active && !nativeDialogOpen && !controller.blocked
  readonly property bool chatFocused: panel.activeFocus || panel.emojiPickerOpen
  readonly property Item surfaceItem: bubble.surfaceItem
  readonly property real originContentOpacity: bubble.originContentOpacity
  readonly property real morphProgress: bubble.progress
  readonly property real capsuleWidth: bubble.capsuleWidth
  readonly property real capsuleHeight: bubble.capsuleHeight
  readonly property var photoPreviewWindow: photoWindow
  signal returnFocusRequested()

  HyprlandFocusGrab {
    id: focusGrab
    // One stable whitelist spans the whole handoff. Removing the photo as it
    // unmaps could clear the grab asynchronously after the chat reclaimed it.
    windows: [root.panelWindow, photoWindow]
    // Never bind active to visibility: clicking another app must release it.
  }
  function focusMessenger() {
    if (!active || nativeDialogOpen || controller.blocked) return;
    focusGrab.active = true;
    if (photoWindow.visible) photoWindow.viewer.forceActiveFocus();
    else panel.focusNavigation();
  }
  onActiveChanged: {
    if (active) Qt.callLater(focusMessenger);
    else {
      focusGrab.active = false;
      nativeDialogOpen = false;
      Qt.callLater(() => root.returnFocusRequested());
    }
  }
  onKeyboardSelectorActiveChanged: {
    if (keyboardSelectorActive) focusGrab.active = false;
    else Qt.callLater(() => {
      // Restore the FocusScope's input without taking OS focus from an app.
      if (root.active && !root.keyboardSelectorActive && root.windowFocused
          && !root.nativeDialogOpen && !root.controller.blocked)
        panel.forceActiveFocus();
    });
  }
  Connections {
    target: root.controller
    function onAboutToShow() { if (root.monitorName === root.controller.targetMonitor) bubble.prepareOpen(); }
    function onFocusSerialChanged() { Qt.callLater(root.focusMessenger); }
    function onBlockedChanged() {
      if (root.controller.blocked) focusGrab.active = false;
      else Qt.callLater(() => {
        if (root.active && root.windowFocused && !root.keyboardSelectorActive && !root.nativeDialogOpen)
          panel.forceActiveFocus();
      });
    }
  }

  BeeperBubble {
    id: bubble
    objectName: "beeperBubble"
    anchors.fill: parent
    expanded: root.active
    barTop: root.barTop
    workAreaTop: root.workAreaTop
    sourceWidth: root.sourceWidth
    sourceHeight: root.sourceHeight
  }
  BeeperPanel {
    id: panel
    parent: bubble.contentItem
    anchors.fill: parent
    beeperData: root.controller.beeperData
    externalPhotoPreview: true
    active: root.active && !root.controller.blocked
    windowFocused: root.windowFocused && (activeFocus || emojiPickerOpen) && !root.nativeDialogOpen && !root.controller.blocked
    enabled: active
    onCloseRequested: root.controller.hide()
    onNativeDialogOpened: { root.nativeDialogOpen = true; focusGrab.active = false; }
    onNativeDialogClosed: {
      root.nativeDialogOpen = false;
      Qt.callLater(() => {
        if (root.active && !root.controller.blocked) {
          focusGrab.active = true;
          panel.forceActiveFocus();
        }
      });
    }
  }
  MessengerPhotoWindow {
    id: photoWindow
    screen: root.panelWindow.screen
    visible: root.active && !root.controller.blocked && panel.photoPreviewOpen
    beeperData: root.controller.beeperData
    attachment: panel.previewAttachment
    onVisibleChanged: if (visible) Qt.callLater(() => {
      if (photoWindow.visible) { focusGrab.active = true; photoWindow.viewer.forceActiveFocus(); }
    })
    onCloseRequested: {
      // Retire the old grab before unmapping the exclusive photo surface.
      // Its delayed cleared event must not cancel the chat's new grab.
      focusGrab.active = false;
      panel.closeModal();
      Qt.callLater(() => {
        if (root.active && !root.controller.blocked) { focusGrab.active = true; panel.forceActiveFocus(); }
      });
    }
  }
  Rectangle {
    parent: bubble.contentItem
    anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 16 }
    width: 250; height: 32; radius: 16; color: Theme.surfaceRaised
    visible: root.active && root.dictating
    z: 3
    Text {
      anchors.centerIn: parent
      text: root.transcribing ? "Dictation · transcribing…" : "●  Dictation in progress"
      color: Theme.state
      font.family: "Ubuntu Nerd Font"; font.pixelSize: Theme.beeperFont.secondary
    }
  }
}
