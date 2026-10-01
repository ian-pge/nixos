import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./BeeperFormat.js" as Format

Rectangle {
  id: root
  objectName: "beeperComposerSurface"
  required property var beeperData
  property bool active: false
  property bool dictating: false
  property bool compact: false
  property real textSize: Theme.beeperFont.body
  property color networkAccent: Theme.secondary
  property string editMessageID: ""
  property string editText: ""
  property bool recording: false
  property bool preparingRecording: false
  property real recordingDuration: 0
  // Vim-style modal editing; the owner turns it on.
  property bool vimEditing: false
  readonly property string vimMode: vimEditor.mode
  property alias input: composer
  readonly property bool emojiPickerOpen: emojiPicker.visible
  readonly property bool canPickEmoji: active && enabled && !!beeperData.currentChatID
    && !beeperData.currentChat?.isReadOnly && !recording && !preparingRecording && !composer.inputMethodComposing
  property var emojiSelection: null
  readonly property bool sendMode: !!composer.text.trim() || !!beeperData.draftAttachment || !!editMessageID
  readonly property bool busy: preparingRecording || beeperData.sending || beeperData.stagingAttachments > 0
  property real sendReveal: sendMode ? 1 : 0
  Behavior on sendReveal { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  signal editTextEdited(string text)
  signal draftTextEdited(string text)
  signal submitRequested()
  signal copyRequested(string text)
  signal pasteAttachmentRequested()
  signal recordingToggleRequested()
  signal attachmentsDropped(var urls)
  implicitHeight: composerColumn.implicitHeight + 8
  color: Theme.surface
  radius: 24
  enabled: !!root.beeperData.currentChatID && !root.beeperData.currentChat?.isReadOnly
  function toggleEmojiPicker() {
    if (emojiPicker.visible) { closeEmojiPicker(true); return; }
    if (!canPickEmoji) return;
    emojiSelection = {chatID: beeperData.currentChatID, editID: editMessageID, text: composer.text,
      start: composer.selectionStart, end: composer.selectionEnd};
    emojiPicker.open();
  }
  function closeEmojiPicker(restoreFocus = false) {
    if (!emojiPicker?.visible) return;
    emojiPicker.close();
    if (restoreFocus && canPickEmoji && emojiSelection?.chatID === beeperData.currentChatID
        && emojiSelection?.editID === editMessageID) {
      composer.forceActiveFocus();
      if (composer.text === emojiSelection.text) composer.select(emojiSelection.start, emojiSelection.end);
    }
  }
  function insertEmoji(emoji) {
    const selection = emojiSelection;
    if (!emoji || !canPickEmoji || selection?.chatID !== beeperData.currentChatID || selection?.editID !== editMessageID) {
      closeEmojiPicker(); return;
    }
    const unchanged = composer.text === selection.text;
    const start = unchanged ? selection.start : composer.selectionStart;
    const end = unchanged ? selection.end : composer.selectionEnd;
    closeEmojiPicker(); composer.forceActiveFocus();
    if (end > start) composer.remove(start, end);
    composer.insert(start, emoji);
    composer.cursorPosition = start + emoji.length;
    composer.deselect();
  }
  onCanPickEmojiChanged: if (!canPickEmoji) closeEmojiPicker()
  onEditMessageIDChanged: closeEmojiPicker()
  onVisibleChanged: if (!visible) closeEmojiPicker()
  Connections {
    target: root.beeperData
    function onCurrentChatIDChanged() { root.closeEmojiPicker(); }
  }
  ColumnLayout {
    id: composerColumn
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
    spacing: 6
    RowLayout {
      visible: !!root.beeperData.replyToMessageID || !!root.editMessageID
      Layout.fillWidth: true
      // Keep the quote and its accent strip inside the composer's rounded corners.
      Layout.leftMargin: 8; Layout.rightMargin: 8; Layout.topMargin: 8
      Text { visible: !!root.editMessageID; Layout.fillWidth: true; text: "Edit message"; color: Theme.sideApplications; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary } }
      BeeperQuote {
        Layout.fillWidth: true
        beeperData: root.beeperData
        messageID: root.editMessageID ? "" : root.beeperData.replyToMessageID
        active: root.active
        textScale: root.textSize / Theme.beeperFont.body
      }
    }
    ColumnLayout {
      visible: root.beeperData.draftAttachments.length > 0; Layout.fillWidth: true
      Layout.leftMargin: 8; Layout.rightMargin: 8
      Layout.topMargin: root.beeperData.replyToMessageID || root.editMessageID ? 0 : 8
      Text {
        visible: root.beeperData.draftAttachments.length > 1
        text: root.beeperData.draftAttachments.length + " files · sent in order"
        color: Theme.inactive; font { family: "Ubuntu Nerd Font"; pixelSize: Theme.beeperFont.secondary }
      }
      ListView {
        id: attachmentList
        objectName: "beeperDraftAttachments"
        Layout.fillWidth: true; Layout.preferredHeight: count ? 88 : 0
        orientation: ListView.Horizontal; spacing: 8; clip: true
        model: root.beeperData.draftAttachments
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.horizontal: ScrollBar {}
        delegate: Item {
          required property var modelData
          required property int index
          width: attachmentList.count === 1 ? attachmentList.width : Math.min(220, attachmentList.width)
          height: 88
          BeeperMedia {
            anchors.fill: parent; anchors.rightMargin: 28
            attachment: modelData; beeperData: root.beeperData; playbackEnabled: root.active
          }
          Button {
            id: removeAttachment
            objectName: "beeperRemoveAttachment" + index
            anchors { top: parent.top; right: parent.right }
            width: 24; height: 24; padding: 0
            hoverEnabled: true
            background: null
            contentItem: Icon {
              opacity: removeAttachment.hovered || removeAttachment.activeFocus ? 1 : 0.65
              name: "x"; size: 12; color: "white"; strokeWidth: 1.5
            }
            Accessible.name: "Remove " + (modelData.fileName || "attachment")
            onClicked: root.beeperData.clearAttachment(index)
          }
        }
      }
    }
    // Vim's / search line, aligned with the text: emoji button, spacing, padding.
    VimSearchPrompt {
      vim: vimEditor
      Layout.fillWidth: true
      Layout.leftMargin: 54; Layout.rightMargin: 8; Layout.topMargin: 6
      Layout.preferredHeight: visible ? implicitHeight : 0
    }
    RowLayout {
      Layout.fillWidth: true; spacing: 4
      Button {
        id: emojiButton
        objectName: "beeperComposerEmoji"
        Layout.preferredWidth: 40; Layout.preferredHeight: 40; Layout.alignment: Qt.AlignBottom
        enabled: root.canPickEmoji
        focusPolicy: Qt.TabFocus
        Accessible.name: "Choose an emoji"
        onClicked: root.toggleEmojiPicker()
        background: Rectangle {
          radius: width / 2
          color: Qt.alpha(root.networkAccent, emojiButton.down ? 0.28
            : root.emojiPickerOpen || emojiButton.hovered || emojiButton.activeFocus ? 0.2 : 0.1)
        }
        contentItem: Icon {
          name: "face-slightly-smiling"; color: root.networkAccent; size: 23
        }
      }
      ScrollView {
        id: composerScroll
        Layout.fillWidth: true; Layout.preferredHeight: Math.max(40, Math.min(160, composer.implicitHeight))
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Binding { target: composerScroll.contentItem; property: "boundsBehavior"; value: Flickable.StopAtBounds }
        Binding { target: composerScroll.contentItem; property: "flickableDirection"; value: Flickable.VerticalFlick }
        clip: true
        TextArea {
          id: composer; objectName: "beeperComposer"
          text: root.editMessageID ? root.editText : root.beeperData.draftText
          placeholderText: root.beeperData.currentChat?.isReadOnly ? "Read-only conversation"
            : root.recording ? "Recording  " + Format.duration(root.recordingDuration)
            : root.preparingRecording ? "Preparing recording…" : root.dictating ? "Dictation in progress…" : "Write a message…"
          // Outside Vim's insert mode, only Vim commands may edit the text.
          readOnly: root.recording || root.preparingRecording || !vimEditor.inserting
          // JetBrains Mono lines are taller than Ubuntu's: 7 + 6 px keep one
          // line within the 40 px row, so the composer still rests at 48 px.
          leftPadding: 10; rightPadding: 6; topPadding: 7; bottomPadding: 6
          color: Theme.foreground; placeholderTextColor: Theme.inactive
          selectionColor: Qt.alpha(Theme.sideApplications, 0.4)
          selectedTextColor: Theme.selectedForeground
          // Terminal-like input: every character takes the same width.
          font { family: "JetBrainsMono Nerd Font"; pixelSize: root.textSize }
          wrapMode: TextEdit.Wrap; selectByMouse: true
          background: null
          cursorDelegate: Rectangle {
            id: caret
            objectName: "beeperComposerCursor"
            width: 3; radius: 1; color: Theme.textCursor
            property bool blinkOn: true
            opacity: composer.cursorVisible && !composer.readOnly && blinkOn ? 1 : 0
            function restartBlink() { blinkOn = true; if (blink.running) blink.restart(); }
            Timer {
              id: blink
              interval: Math.max(1, Qt.styleHints.cursorFlashTime / 2); repeat: true
              running: composer.activeFocus && composer.cursorVisible && !composer.readOnly && Qt.styleHints.cursorFlashTime > 0
              onTriggered: caret.blinkOn = !caret.blinkOn
              onRunningChanged: caret.blinkOn = true
            }
            Connections {
              target: composer
              function onCursorRectangleChanged() { caret.restartBlink(); }
              function onCursorVisibleChanged() { caret.restartBlink(); }
            }
          }
          onTextChanged: {
            if (!root.active || !activeFocus) return;
            if (root.editMessageID) { if (text !== root.editText) root.editTextEdited(text); }
            else if (text !== root.beeperData.draftText) root.draftTextEdited(text);
          }
          Keys.onPressed: event => {
            if (vimEditor.handleKeyEvent(event)) return;
            if (Format.shouldSend(event.key, event.modifiers, inputMethodComposing)) { if (!event.isAutoRepeat) root.submitRequested(); event.accepted = true; }
            // Normal mode is read-only, so canPaste is false there without meaning "no text".
            else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)
                && ((!canPaste && vimEditor.inserting) || (event.modifiers & Qt.ShiftModifier))) { root.pasteAttachmentRequested(); event.accepted = true; }
          }
        }
      }
      Button {
        id: actionButton
        objectName: "beeperComposerAction"
        Layout.preferredWidth: 40; Layout.preferredHeight: 40; Layout.alignment: Qt.AlignBottom
        enabled: root.recording || (!root.busy && !composer.inputMethodComposing && root.beeperData.connected)
        focusPolicy: Qt.TabFocus
        Accessible.name: root.recording ? "Finish recording" : root.sendMode ? (root.editMessageID ? "Save message" : "Send message") : "Record a voice message"
        onClicked: {
          if (root.recording) root.recordingToggleRequested();
          else if (root.sendMode) root.submitRequested();
          else root.recordingToggleRequested();
        }
        background: Rectangle {
          radius: width / 2
          color: Qt.alpha(root.recording ? Theme.error : root.networkAccent,
            actionButton.down ? 0.28 : actionButton.hovered || actionButton.activeFocus ? 0.2 : 0.1)
          Icon {
            objectName: "beeperComposerStopIcon"
            anchors.centerIn: parent
            name: "square"; size: 16
            color: Theme.error
            visible: root.recording && !root.busy
          }
        }
        contentItem: Item {
          Icon {
            size: 23
            objectName: "beeperComposerMicrophone"
            anchors.centerIn: parent; name: "mic"
            color: root.networkAccent
            opacity: root.busy || root.recording ? 0 : 1 - root.sendReveal
            scale: 0.8 + 0.2 * opacity

          }
          Icon {
            objectName: "beeperComposerSendIcon"
            anchors.centerIn: parent; name: root.editMessageID ? "check" : "send"
            color: root.networkAccent
            opacity: root.busy || root.recording ? 0 : root.sendReveal
            scale: 0.8 + 0.2 * opacity
            size: 21
          }
          Icon { anchors.centerIn: parent; visible: root.busy; name: "loader-circle"; spinning: true; color: root.networkAccent; size: 23 }
        }
      }
    }
  }
  BeeperEmojiPicker {
    id: emojiPicker
    parent: root
    y: -height - 8
    accent: root.networkAccent
    onEmojiSelected: emoji => root.insertEmoji(emoji)
    onCancelRequested: root.closeEmojiPicker(true)
  }
  DropArea {
    anchors.fill: parent
    onDropped: drop => { if (drop.hasUrls && drop.urls.length) { root.attachmentsDropped(Array.from(drop.urls, url => url.toString())); drop.acceptProposedAction(); } }
  }
  AcceleratedScroll { flickable: composerScroll.contentItem }
  VimEditing {
    id: vimEditor
    objectName: "beeperComposerVim"
    target: composer
    active: root.vimEditing && !root.recording && !root.preparingRecording
    onSubmitRequested: root.submitRequested()
    onCopyRequested: text => root.copyRequested(text)
  }
}
