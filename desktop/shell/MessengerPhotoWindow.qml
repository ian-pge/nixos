import QtQuick
import Quickshell
import Quickshell.Wayland
import "../features/messenger"
import "../ui/Theme.js" as Theme

// The viewer owns the short opacity fade. No compositor blur or second layer
// animation (Hyprland rule `no_anim`) should extend it or move the image.
PanelWindow {
  id: root
  objectName: "messengerPhotoWindow"
  required property var beeperData
  property bool open: false
  property var attachment: null
  property Item previewOrigin: null
  property bool editing: false
  readonly property Item viewer: editing ? imageEditor.item : photo
  signal closeRequested()
  signal stepRequested(int delta)
  signal imageEdited(var attachment)
  visible: open
  anchors { top: true; bottom: true; left: true; right: true }
  // Drawing covers the monitor: expose an opaque surface so the compositor
  // can skip the glass and other windows behind it while the pointer moves.
  color: root.editing ? Theme.background : "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "quickshell-messenger-photo"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  BeeperPhotoViewer {
    id: photo
    anchors.fill: parent
    beeperData: root.beeperData
    attachment: root.attachment
    previewOrigin: root.previewOrigin
    active: root.visible
    visible: !root.editing
    focus: !root.editing
    onCloseRequested: root.closeRequested()
    onStepRequested: delta => root.stepRequested(delta)
  }
  Loader {
    id: imageEditor
    anchors.fill: parent
    focus: root.editing
    active: root.visible && root.editing
    onLoaded: item.forceActiveFocus()
    sourceComponent: BeeperImageEditor {
      beeperData: root.beeperData
      attachment: root.attachment
      active: root.visible && root.editing
      onCancelRequested: root.closeRequested()
      onSaved: attachment => root.imageEdited(attachment)
    }
  }
}
