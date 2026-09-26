import QtQuick
import Quickshell
import Quickshell.Wayland
import "../features/messenger"

PanelWindow {
  id: root
  objectName: "messengerPhotoWindow"
  required property var beeperData
  property var attachment: null
  property alias viewer: photo
  signal closeRequested()
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "quickshell-messenger-photo"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  BeeperPhotoViewer {
    id: photo
    anchors.fill: parent
    beeperData: root.beeperData
    attachment: root.attachment
    active: root.visible
    focus: true
    onCloseRequested: root.closeRequested()
  }
}
