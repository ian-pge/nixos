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
  property Item previewOrigin: null
  property var linkChoices: []
  property bool vimEditing: false
  property color accent: Theme.sideApplications
  property bool externalPhotoPreview: false
  readonly property bool photoPreview: root.mode === "media"
    && ["image", "gif", "video"].includes(Format.attachmentType(previewAttachment || {}))
  readonly property Item surface: photoPreview ? photoViewer : modalSurface
  signal closeRequested()
  signal linkSelected(string url)
  signal previewStepRequested(int delta)
  function requestClose() {
    if (photoPreview && !externalPhotoPreview) photoViewer.requestClose();
    else closeRequested();
  }
  readonly property string shortcutsHelp: [
    "GENERAL · outside text input",
    "Super / Cmd + D     Show / hide messenger",
    "?     Open / close this help",
    "Tab / Shift+Tab     Next / previous network",
    "j / k     Next / previous conversation",
    "h     Return to conversations",
    "l / Enter     Write in the selected conversation",
    "Ctrl + j / k     Next / previous message (also while typing)",
    "gg / G     First / last conversation or message",
    "Ctrl + u     Scroll up half a page",
    "",
    "COMPOSER",
    "Enter     Send message / save an edit",
    "Shift + Enter     New line",
    "Ctrl + s     Open / close emoji picker",
    "Ctrl + d     Start / finish a voice recording",
    "A finished recording is attached to the draft, not sent",
    "Ctrl + v     Paste text, or an image when no text is available",
    "Ctrl + Shift + v     Paste an image attachment"
  ].concat(vimEditing ? vimHelp : [], [
    "",
    "EMOJI PICKER",
    "h / j / k / l or arrows     Move through the grid",
    "/     Focus emoji search (English / French)",
    "Enter in search     Back to the results, on the first match",
    "Enter / Space in the grid     Insert the selected emoji",
    "Tab / Shift+Tab     Switch between search and grid",
    "Down from search     Return to the results grid",
    "Enter     Insert selected emoji",
    "Space in the grid     Insert selected emoji",
    "Esc / Ctrl + s     Cancel and return to the draft",
    "",
    "CONVERSATIONS · outside text input",
    "m / n     Mark as read / unread",
    "u     Toggle unread-first sorting",
    "a     Switch between inbox and Low Priority",
    "Shift + A     Move selected conversation to / from Low Priority",
    "Low Priority stays out of the inbox; mentions and replies may still notify",
    "",
    "SELECTED MESSAGE · outside text input",
    "r / e     Reply / edit your own message",
    "o     Open first attachment",
    "Space     Open link(s), otherwise play / open media",
    "y     Copy the whole message text",
    Format.quickReactions(root.beeperData.currentChat).map((reaction, index) => (index + 1) + " " + reaction).join("   "),
    "Digits toggle your reaction; another digit replaces it",
    "",
    "TEXT SELECTION · mouse",
    "Drag over a message     Select part of its text",
    "y / Ctrl + c     Copy the selection (y also clears it)",
    "Esc     Clear the selection",
    "",
    "SEARCH",
    "/     Search conversations",
    "Ctrl + /     Search messages in the current conversation",
    "Enter     Select a chat / confirm message search",
    "n / N, j / k, Ctrl + j / k     Next / previous message match",
    "Esc     Close search",
    "",
    "LINK CHOOSER",
    "j / k or Down / Up     Select a link",
    "Enter     Open the selected link",
    "Esc     Cancel",
    "",
    "MEDIA",
    "Space on selected audio     Play / pause",
    "Esc while audio is playing     Pause before other Esc actions",
    "Audio continues while navigating or hiding the messenger",
    "Space / Esc on a fullscreen photo     Close photo",
    "h / l on a fullscreen photo     Previous / next photo in this chat",
    "Enter on fullscreen media     Save a copy to Downloads",
    "Space on fullscreen video     Play / pause",
    "h / l on fullscreen video     Back / forward 5 seconds",
    "Esc on fullscreen video     Close video",
    "",
    "CHAT TEXT SIZE",
    "Ctrl + wheel or Ctrl + + / -     Zoom in / out",
    "Ctrl + 0     Reset text size",
    "",
    "ESCAPE · after pausing any playing audio",
    "Cancel popup, reply / edit, then remove attachment",
    "Return to conversations, leave Low Priority, then close messenger",
    "Text and unsent drafts are preserved"
  ]).join("\n")
  readonly property var vimHelp: [
    "",
    "COMPOSER · VIM MODE",
    "Writing starts in insert mode",
    "Esc     Normal mode; in normal mode, the Escape steps below",
    "i / a / I / A / o / O     Insert here / after / line start / line end / below / above",
    "h / j / k / l     Move; j / k follow wrapped lines",
    "w / b / e · W / B / E     Next word / previous word / word end",
    "0 / ^ / $ · gg / G     Line start / first letter / line end · first / last line",
    "f / t / F / T + character, then ; / ,     Find in the line, repeat",
    "/ + text, then Enter     Search the message, ignoring case; Esc cancels",
    "n / N     Next / previous match",
    "d / c / y + motion or object     Delete / change / copy, with counts like 2dw",
    "dd / cc / yy     Whole lines",
    "iw aw · i\" a\" · i( a( · i[ a[ · i{ a{     Word, quotes and brackets objects",
    "x / X / s / S / D / C / Y     Short edits; Y copies to the line end",
    "r + character / ~ / J     Replace / switch case / join lines",
    "p / P     Paste after / before",
    "u / Ctrl + r     Undo / redo",
    "v / V     Select characters / lines",
    "Enter     Send from normal mode",
    "Copies also go to the system clipboard"
  ]
  function scrollHelp(delta) {
    const view = helpScroll;
    helpWheel.reset(); view.cancelFlick();
    const start = view.originY || 0, end = start + Math.max(0, view.contentHeight - view.height);
    view.contentY = Math.max(start, Math.min(end, view.contentY + delta));
  }
  onModeChanged: if (mode === "help") Qt.callLater(() => { if (root.mode === "help") root.scrollHelp(-Infinity); })
  onLinkChoicesChanged: linksList.currentIndex = linkChoices.length ? 0 : -1
  visible: root.mode === "help" || root.mode === "links" || root.mode === "media" && !(photoPreview && externalPhotoPreview)
  color: photoPreview ? "transparent" : Qt.alpha(Theme.background, 0.55)
  MouseArea { anchors.fill: parent; onClicked: root.requestClose() }
  Rectangle {
    id: modalSurface
    objectName: "beeperModalSurface"
    visible: !root.photoPreview
    anchors.centerIn: parent
    width: Math.min(parent.width - 60, root.mode === "media" ? 760 : root.mode === "help" ? 700 : 540)
    height: Math.min(parent.height - 60, modalColumn.implicitHeight + 36)
    radius: 18; color: Theme.surface
    clip: true
    MouseArea { anchors.fill: parent }
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape || root.mode === "media" && event.key === Qt.Key_Space
          || root.mode === "help" && (event.key === Qt.Key_Question || event.text === "?")) {
        if (!event.isAutoRepeat) root.closeRequested();
        event.accepted = true;
      } else if (root.mode === "help" && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) root.scrollHelp(40);
        else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) root.scrollHelp(-40);
        else if (event.key === Qt.Key_PageDown) root.scrollHelp(helpScroll.height * 0.8);
        else if (event.key === Qt.Key_PageUp) root.scrollHelp(-helpScroll.height * 0.8);
        else if (event.key === Qt.Key_Home) root.scrollHelp(-Infinity);
        else if (event.key === Qt.Key_End) root.scrollHelp(Infinity);
        else return;
        event.accepted = true;
      } else if (root.mode === "links" && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
          linksList.currentIndex = Math.min(root.linkChoices.length - 1, linksList.currentIndex + 1); event.accepted = true;
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
          linksList.currentIndex = Math.max(0, linksList.currentIndex - 1); event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (!event.isAutoRepeat && root.linkChoices[linksList.currentIndex]) root.linkSelected(root.linkChoices[linksList.currentIndex].url);
          event.accepted = true;
        }
      }
    }
    ColumnLayout {
      id: modalColumn
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 12
      RowLayout {
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; text: root.mode === "help" ? "Keyboard shortcuts" : root.mode === "links" ? "Open a link" : "Attachment"; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.title; weight: Font.Medium } }
        BeeperButton { text: "×"; onClicked: root.closeRequested() }
      }
      ListView {
        id: linksList
        objectName: "beeperLinksList"
        visible: root.mode === "links"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Math.max(72, root.height - 180))
        model: root.linkChoices
        clip: true; spacing: 6
        acceptedButtons: Qt.NoButton
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        keyNavigationEnabled: false
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        AcceleratedScroll { flickable: linksList; inputEnabled: root.mode === "links" }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: BeeperButton {
          id: linkButton
          required property var modelData
          required property int index
          width: linksList.width; height: 72
          prominent: index === linksList.currentIndex
          accent: root.accent; focusPolicy: Qt.NoFocus
          Accessible.name: (modelData.title ? modelData.title + ". " : "") + modelData.url
          onClicked: root.linkSelected(modelData.url)
          ToolTip.visible: hovered
          ToolTip.text: modelData.url
          contentItem: Column {
            spacing: 4
            Text {
              width: parent.width
              text: (linkButton.index + 1) + ". " + (linkButton.modelData.title || linkButton.modelData.url)
              textFormat: Text.PlainText; elide: Text.ElideRight
              color: linkButton.prominent ? root.accent : Theme.foreground
              font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control; weight: Font.Medium }
            }
            Text {
              width: parent.width
              visible: !!linkButton.modelData.title
              text: linkButton.modelData.url; textFormat: Text.PlainText; elide: Text.ElideMiddle
              color: Theme.secondary
              font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
            }
          }
        }
      }
      Text {
        visible: root.mode === "links"; Layout.fillWidth: true
        text: "J / K   Select     Enter   Open     Esc   Cancel"
        color: Theme.secondary
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
      }
      Flickable {
        id: helpScroll
        objectName: "beeperHelpScroll"
        visible: root.mode === "help"; Layout.fillWidth: true
        Layout.minimumHeight: 0
        Layout.maximumHeight: Math.max(80, root.height - 220)
        Layout.preferredHeight: Math.min(helpText.implicitHeight, Math.max(80, root.height - 220))
        contentWidth: width; contentHeight: helpText.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        acceptedButtons: Qt.NoButton
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Text {
          id: helpText
          objectName: "beeperKeyboardHelp"
          width: Math.max(0, helpScroll.width - 12)
          text: root.shortcutsHelp; textFormat: Text.PlainText
          color: Theme.secondary; wrapMode: Text.Wrap; lineHeight: 1.45
          font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control }
        }
      }
      BeeperMedia {
        visible: root.mode === "media" && !root.photoPreview; Layout.fillWidth: true
        Layout.preferredHeight: visible ? implicitHeight : 0
        attachment: root.previewAttachment || {}; beeperData: root.beeperData
        expanded: true; playbackEnabled: visible && root.active; renderEnabled: visible
      }
      Text {
        objectName: "beeperHelpFooter"
        visible: root.mode === "help"; Layout.fillWidth: true
        text: "J / K / arrows · Scroll    PgUp / PgDn · Page    Home / End\nEsc / ? · Close"
        color: root.accent; wrapMode: Text.Wrap
        font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.caption }
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
    previewOrigin: root.previewOrigin
    onCloseRequested: root.closeRequested()
    onStepRequested: delta => root.previewStepRequested(delta)
  }
  AcceleratedScroll { id: helpWheel; flickable: helpScroll; inputEnabled: root.mode === "help" }
}
