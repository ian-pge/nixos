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
  property var attachmentChoices: []
  property bool vimEditing: false
  property color accent: Theme.sideApplications
  property bool externalPhotoPreview: false
  readonly property bool imageEditing: mode === "draw"
  readonly property bool photoPreview: root.mode === "media"
    && ["image", "gif", "video"].includes(Format.attachmentType(previewAttachment || {}))
  readonly property Item surface: imageEditing ? imageEditor.item : photoPreview ? photoViewer : modalSurface
  signal closeRequested()
  signal attachmentSelected(int index)
  signal downloadRequested()
  signal previewStepRequested(int delta)
  signal imageEdited(var attachment)
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
    "Enter     Write in the selected conversation",
    "Ctrl + h / l     Focus conversations / composer (also while typing)",
    "Ctrl + j / k     Next / previous message (also while typing)",
    "gg / G     First / last conversation or message",
    "Ctrl + u     Scroll up half a page",
    "",
    "COMPOSER",
    "Enter     Send message / save an edit",
    "Shift + Enter     New line",
    "Ctrl + s     Open / close emoji picker",
    "Ctrl + d     Start / finish a voice recording",
    "Enter while recording     Finish; press Enter again to send",
    "Esc while recording     Cancel the recording",
    "Ctrl + f     Attach files with Yazi (sent in selection order)",
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
    "q in gausst     Show Shelby's messages in 3 lines / in full",
    "Low Priority stays out of the inbox; mentions and replies may still notify",
    "",
    "SELECTED MESSAGE · outside text input",
    "r / e     Reply / edit your own message",
    "Space     Play / pause audio only",
    "o     Open attachment; choose one if there are several",
    "i     Jump to the original message of a reply",
    "d     Download all attachments in the selected message",
    "l     Open the first link in the message",
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
    "Tab / Shift+Tab in conversation search     Select next / previous result",
    "Ctrl + j / k in conversation search     Select next / previous result",
    "Enter / Ctrl + l in conversation search     Open selected chat and close search",
    "Enter in message search     Confirm message search",
    "n / N, j / k, Ctrl + j / k     Next / previous message match",
    "Esc     Close search",
    "",
    "ATTACHMENT CHOOSER",
    "j / k or Down / Up     Select an attachment",
    "Enter / o     Open the selected attachment",
    "d     Download all attachments in this message",
    "Esc     Cancel",
    "",
    "MEDIA",
    "Space on selected audio     Play / pause",
    "h / l while audio is playing · outside text input     Back / forward 5 seconds",
    "Esc while audio is playing     Pause before other Esc actions",
    "Audio continues while navigating or hiding the messenger",
    "o / Esc on a fullscreen photo     Close photo",
    "h / l on a fullscreen photo     Previous / next photo in this chat",
    "d on fullscreen media     Download the displayed photo or video",
    "Space on fullscreen video     Play / pause",
    "h / l on fullscreen video     Back / forward 5 seconds",
    "o / Esc on fullscreen video     Close video",
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
  onAttachmentChoicesChanged: attachmentsList.currentIndex = attachmentChoices.length ? 0 : -1
  visible: root.mode === "help" || root.mode === "attachments" || root.mode === "media" && !(photoPreview && externalPhotoPreview)
    || imageEditing && !externalPhotoPreview
  color: photoPreview || imageEditing ? "transparent" : Qt.alpha(Theme.background, 0.55)
  MouseArea { anchors.fill: parent; onClicked: root.requestClose() }
  Rectangle {
    id: modalSurface
    objectName: "beeperModalSurface"
    visible: !root.photoPreview && !root.imageEditing
    anchors.centerIn: parent
    width: Math.min(parent.width - 60, root.mode === "media" ? 760 : root.mode === "help" ? 700 : 540)
    height: Math.min(parent.height - 60, modalColumn.implicitHeight + 36)
    radius: 18; color: Theme.surface
    clip: true
    MouseArea { anchors.fill: parent }
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape || root.mode === "media" && event.key === Qt.Key_O
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
      } else if (root.mode === "attachments" && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier))) {
        if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
          attachmentsList.currentIndex = Math.min(root.attachmentChoices.length - 1, attachmentsList.currentIndex + 1); event.accepted = true;
        } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
          attachmentsList.currentIndex = Math.max(0, attachmentsList.currentIndex - 1); event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_O) {
          if (!event.isAutoRepeat && root.attachmentChoices[attachmentsList.currentIndex]) root.attachmentSelected(attachmentsList.currentIndex);
          event.accepted = true;
        } else if (event.key === Qt.Key_D) {
          if (!event.isAutoRepeat) root.downloadRequested();
          event.accepted = true;
        }
      }
    }
    ColumnLayout {
      id: modalColumn
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 } spacing: 12
      RowLayout {
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; text: root.mode === "help" ? "Keyboard shortcuts" : root.mode === "attachments" ? "Open an attachment" : "Attachment"; color: Theme.foreground; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.title; weight: Font.Medium } }
        BeeperButton { iconName: "x"; Accessible.name: "Close"; onClicked: root.closeRequested() }
      }
      ListView {
        id: attachmentsList
        objectName: "beeperAttachmentsList"
        visible: root.mode === "attachments"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Math.max(72, root.height - 180))
        model: root.attachmentChoices
        clip: true; spacing: 6
        acceptedButtons: Qt.NoButton
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        keyNavigationEnabled: false
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        AcceleratedScroll { flickable: attachmentsList; inputEnabled: root.mode === "attachments" }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: BeeperButton {
          id: attachmentButton
          required property var modelData
          required property int index
          readonly property var fileStyle: Format.attachmentFileStyle(modelData.attachment)
          width: attachmentsList.width; height: 72
          prominent: index === attachmentsList.currentIndex
          accent: root.accent; focusPolicy: Qt.NoFocus
          Accessible.name: modelData.title
          onClicked: root.attachmentSelected(index)
          ToolTip.visible: hovered
          ToolTip.text: modelData.title
          contentItem: RowLayout {
            spacing: 12
            Icon {
              objectName: "beeperAttachmentChoiceIcon"
              size: 32; name: attachmentButton.fileStyle.icon
              color: Theme.beeperAttachmentColors[attachmentButton.fileStyle.kind]
            }
            ColumnLayout {
              Layout.fillWidth: true; spacing: 4
              Text {
                Layout.fillWidth: true
                text: (attachmentButton.index + 1) + ". " + attachmentButton.modelData.title
                textFormat: Text.PlainText; elide: Text.ElideRight
                color: attachmentButton.prominent ? root.accent : Theme.foreground
                font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.control; weight: Font.Medium }
              }
              Text {
                Layout.fillWidth: true
                text: [attachmentButton.fileStyle.label, Format.bytes(attachmentButton.modelData.attachment?.fileSize)].filter(Boolean).join(" · ")
                textFormat: Text.PlainText; elide: Text.ElideRight
                color: Theme.secondary
                font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
              }
            }
          }
        }
      }
      Text {
        visible: root.mode === "attachments"; Layout.fillWidth: true
        text: "J / K   Select     Enter / O   Open     D   Download all     Esc   Cancel"
        wrapMode: Text.Wrap
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
  Loader {
    id: imageEditor
    anchors.fill: parent
    active: root.active && root.imageEditing && !root.externalPhotoPreview
    onLoaded: item.forceActiveFocus()
    sourceComponent: BeeperImageEditor {
      beeperData: root.beeperData
      attachment: root.previewAttachment
      active: root.active && root.imageEditing
      accent: root.accent
      onCancelRequested: root.closeRequested()
      onSaved: attachment => root.imageEdited(attachment)
    }
  }
  AcceleratedScroll { id: helpWheel; flickable: helpScroll; inputEnabled: root.mode === "help" }
}
