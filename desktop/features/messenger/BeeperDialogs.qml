import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Rectangle {
  id: root
  required property var beeperData
  property string mode: ""
  property bool active: false
  property var previewAttachment: null
  property bool externalPhotoPreview: false
  readonly property bool photoPreview: root.mode === "media"
    && ["image", "gif", "video"].includes(Format.attachmentType(previewAttachment || {}))
  readonly property Item surface: photoPreview ? photoViewer : modalSurface
  signal closeRequested()
  visible: root.mode === "help" || root.mode === "media" && !(photoPreview && externalPhotoPreview)
  color: photoPreview ? "transparent" : Qt.alpha(Theme.background, 0.55)
  MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
  Rectangle {
    id: modalSurface
    objectName: "beeperModalSurface"
    visible: !root.photoPreview
    anchors.centerIn: parent
    width: Math.min(parent.width - 60, root.mode === "media" ? 760 : 540)
    height: Math.min(parent.height - 60, modalColumn.implicitHeight + 36)
    radius: 18; color: Theme.surface
    clip: true
    MouseArea { anchors.fill: parent }
    Keys.onPressed: event => {
      if (event.key !== Qt.Key_Escape && !(root.mode === "media" && event.key === Qt.Key_Space)) return;
      if (!event.isAutoRepeat) root.closeRequested();
      event.accepted = true;
    }
    ColumnLayout {
      id: modalColumn
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 12
      RowLayout {
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; text: root.mode === "help" ? "Keyboard shortcuts" : "Attachment"; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.title; weight: Font.Medium } }
        BeeperButton { text: "×"; onClicked: root.closeRequested() }
      }
      ScrollView {
        id: helpScroll
        objectName: "beeperHelpScroll"
        visible: root.mode === "help"; Layout.fillWidth: true
        Layout.preferredHeight: Math.min(helpText.implicitHeight, Math.max(80, root.height - 180))
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Text {
          id: helpText
          width: helpScroll.availableWidth
          text: "Tab / Shift+Tab     Next / previous network\nj / k     Next / previous conversation\nCtrl + j / k     Next / previous message\nh / l     Conversations / select a message\ngg / G     First / last item\nCtrl + d / u     Scroll half a page\n/     Search conversations\nCtrl + /     Search text in this conversation\nEnter     Confirm search, then n / N or j / k for matches\nEsc     Close conversation search\nm     Mark conversation as read\nn     Mark conversation as unread (outside search)\nu     Toggle unread-first / normal order\na     Switch between inbox and archives only\nShift + A     Archive / restore selected conversation\nEnter     Write a message / send while typing\nShift + Enter     New line\n"
            + Format.quickReactions(root.beeperData.currentChat).map((reaction, index) => (index + 1) + " " + reaction).join("   ")
            + "\nReact to the selected message outside text input\nSpace     Play / pause audio or open photo / video\nVideo: Space     Play / pause\nVideo: h / l     Back / forward 5 seconds\nVideo: Esc     Close fullscreen\nr / e / o     Reply / edit / open media\nCtrl + wheel or + / −     Chat text size\nCtrl + 0     Reset chat text size\nCtrl + Shift + v     Paste attachment\nEsc     Cancel reply / edit, remove attachment, return to conversations, hide archives, then close panel"
          color: Theme.secondary; wrapMode: Text.Wrap; lineHeight: 1.65
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
        }
      }
      BeeperMedia {
        visible: root.mode === "media" && !root.photoPreview; Layout.fillWidth: true
        Layout.preferredHeight: visible ? implicitHeight : 0
        attachment: root.previewAttachment || {}; beeperData: root.beeperData
        expanded: true; playbackEnabled: visible && root.active; renderEnabled: visible
      }
    }
  }
  BeeperPhotoViewer {
    id: photoViewer
    anchors.fill: parent
    visible: root.photoPreview && !root.externalPhotoPreview
    active: root.active && visible
    beeperData: root.beeperData
    attachment: root.previewAttachment
    onCloseRequested: root.closeRequested()
  }
  AcceleratedScroll { flickable: helpScroll.contentItem; inputEnabled: root.mode === "help" }
}
