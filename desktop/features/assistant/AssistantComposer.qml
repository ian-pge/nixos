import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../ui"
import "../../ui/Theme.js" as Theme
import "./AssistantFormat.js" as Format

// Composer of the messenger, reduced to text: reset on the left, then the
// draft, then one action button (send · stop the reply · unload the model).
Rectangle {
  id: root
  objectName: "assistantComposerSurface"
  required property var assistantData
  property bool active: false
  property bool expanded: false
  property bool vimEditing: true
  property real textSize: 18
  property color accent: Theme.flamingo
  property alias input: composer
  readonly property string vimMode: vimEditor.mode
  readonly property bool sendMode: !!composer.text.trim()
  readonly property bool busy: assistantData.sending || assistantData.busy
  readonly property bool replyPending: assistantData.generating
  readonly property bool canReset: active && !busy && !composer.inputMethodComposing
    && (assistantData.messages.length > 0 || replyPending)
  readonly property bool canUnload: active && assistantData.local && !busy && !composer.inputMethodComposing
  property real sendReveal: sendMode ? 1 : 0
  Behavior on sendReveal { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  signal submitRequested()
  signal copyRequested(string text)
  signal switchRequested(int delta)
  implicitHeight: column.implicitHeight + 8
  color: Theme.surface
  // One line: a capsule whose round ends hold the buttons, centered at any text
  // size. Several lines: 24 px corners, the buttons concentric with the bottom ones.
  readonly property bool oneLine: !expanded && composer.lineCount <= 1 && !vimEditor.searching
  radius: oneLine ? height / 2 : 24
  // Distance from the bottom edge to the buttons' centers, for the thinking dot.
  readonly property real buttonCenter: oneLine ? height / 2 : 24
  readonly property real capInset: oneLine ? Math.max(0, height / 2 - 24) : 0

  // A remote model has nothing to unload: its idle button is send.
  readonly property bool unloadMode: assistantData.local && !sendMode
  function act() {
    if (replyPending) assistantData.stopReply();
    else if (sendMode) submitRequested();
    else if (canUnload) assistantData.unloadModel();
  }

  ColumnLayout {
    id: column
    anchors { fill: parent; margins: 4 }
    spacing: 6
    // Vim's / search line, aligned with the text after the reset button.
    VimSearchPrompt {
      vim: vimEditor
      Layout.fillWidth: true
      Layout.leftMargin: 54; Layout.rightMargin: 8; Layout.topMargin: 6
      Layout.preferredHeight: visible ? implicitHeight : 0
    }
    RowLayout {
      Layout.fillWidth: true; Layout.fillHeight: root.expanded; spacing: 4
      Button {
        id: resetButton
        objectName: "assistantReset"
        Layout.preferredWidth: 40; Layout.preferredHeight: 40
        Layout.alignment: root.oneLine ? Qt.AlignVCenter : Qt.AlignBottom
        Layout.leftMargin: root.capInset
        enabled: root.canReset
        focusPolicy: Qt.TabFocus
        Accessible.name: "Reset " + root.assistantData.title + " conversation and context"
        ToolTip.visible: hovered; ToolTip.delay: 600
        ToolTip.text: "Reset conversation (Ctrl+S) · Keep unsent draft"
        onClicked: root.assistantData.resetConversation()
        background: Rectangle {
          radius: width / 2
          color: Qt.alpha(root.accent, resetButton.down ? 0.28 : resetButton.hovered || resetButton.activeFocus ? 0.2 : 0.1)
        }
        contentItem: Icon {
          name: root.assistantData.resetting ? "loader-circle" : "rotate-ccw"
          spinning: root.assistantData.resetting
          color: root.accent; size: 23
          opacity: resetButton.enabled || root.assistantData.resetting ? 1 : 0.45
        }
      }
      ScrollView {
        id: scroll
        Layout.fillWidth: true; Layout.preferredHeight: Math.max(40, Math.min(160, composer.implicitHeight))
        Layout.fillHeight: root.expanded
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Binding { target: scroll.contentItem; property: "boundsBehavior"; value: Flickable.StopAtBounds }
        Binding { target: scroll.contentItem; property: "flickableDirection"; value: Flickable.VerticalFlick }
        clip: true
        TextArea {
          id: composer
          objectName: "assistantComposer"
          height: Math.max(implicitHeight, scroll.availableHeight)
          text: root.assistantData.draftText
          placeholderText: "Ask " + root.assistantData.title + "…"
          // Outside Vim's insert mode, only Vim commands may edit the text.
          readOnly: !vimEditor.inserting
          leftPadding: 10; rightPadding: 6; topPadding: 7; bottomPadding: 6
          color: Theme.foreground; placeholderTextColor: Theme.inactive
          selectionColor: Qt.alpha(root.accent, 0.4); selectedTextColor: Theme.selectedForeground
          font { family: "JetBrainsMono Nerd Font"; pixelSize: root.textSize }
          wrapMode: TextEdit.Wrap; selectByMouse: true
          background: null
          cursorDelegate: Rectangle {
            id: caret
            objectName: "assistantComposerCursor"
            width: 3; radius: 1; color: Theme.textCursor
            property bool blinkOn: true
            opacity: composer.cursorVisible && !composer.readOnly && blinkOn ? 1 : 0
            // Typing or moving the caret keeps it solid; blinking resumes at rest.
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
              function onTextChanged() { caret.restartBlink(); }
            }
          }
          onTextChanged: if (activeFocus && text !== root.assistantData.draftText) root.assistantData.draftText = text
          Keys.onPressed: event => {
            // Tab outside insert mode switches model, as in the history.
            if (!vimEditor.inserting && (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
              if (!event.isAutoRepeat) root.switchRequested(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
              event.accepted = true;
              return;
            }
            if (vimEditor.handleKeyEvent(event)) return;
            if (Format.shouldSend(event.key, event.modifiers, inputMethodComposing)) {
              if (!event.isAutoRepeat) root.submitRequested();
              event.accepted = true;
            }
          }
        }
      }
      Button {
        id: actionButton
        objectName: "assistantAction"
        Layout.preferredWidth: 40; Layout.preferredHeight: 40
        Layout.alignment: root.oneLine ? Qt.AlignVCenter : Qt.AlignBottom
        Layout.rightMargin: root.capInset
        enabled: !root.assistantData.busy && (root.replyPending || !root.assistantData.sending && !composer.inputMethodComposing
          && (root.sendMode || root.unloadMode))
        focusPolicy: Qt.TabFocus
        Accessible.name: root.replyPending ? "Stop the reply" : root.unloadMode ? "Unload Qwen from GPU" : "Send message"
        ToolTip.visible: hovered; ToolTip.delay: 600
        ToolTip.text: root.busy ? "Please wait…" : root.replyPending ? "Stop the reply"
          : root.unloadMode ? "Unload model from GPU (Ctrl+D)" : "Send message"
        onClicked: root.act()
        background: Rectangle {
          radius: width / 2
          color: Qt.alpha(root.accent, actionButton.down ? 0.28 : actionButton.hovered || actionButton.activeFocus ? 0.2 : 0.1)
          Icon {
            objectName: "assistantStopIcon"
            anchors.centerIn: parent
            name: "square"; size: 16; color: root.accent
            visible: root.replyPending && !root.busy
          }
        }
        contentItem: Item {
          Icon {
            objectName: "assistantUnloadIcon"
            anchors.centerIn: parent; name: "power"; size: 23
            color: root.accent
            opacity: root.busy || root.replyPending || !root.assistantData.local ? 0 : 1 - root.sendReveal
            scale: 0.8 + 0.2 * opacity
          }
          Icon {
            objectName: "assistantSendIcon"
            anchors.centerIn: parent; name: "send"; size: 21
            color: root.accent
            opacity: root.busy || root.replyPending ? 0 : root.assistantData.local ? root.sendReveal : 1
            scale: 0.8 + 0.2 * opacity
          }
          Icon { anchors.centerIn: parent; visible: root.busy; name: "loader-circle"; spinning: true; color: root.accent; size: 23 }
        }
      }
    }
  }
  AcceleratedScroll { flickable: scroll.contentItem }
  VimEditing {
    id: vimEditor
    objectName: "assistantComposerVim"
    target: composer
    active: root.vimEditing
    onSubmitRequested: root.submitRequested()
    onCopyRequested: text => root.copyRequested(text)
  }
}
