import QtQuick

FocusScope {
  id: root

  required property bool active
  required property bool captureInput
  property var previousFocus: null
  signal dismissed()

  visible: active

  function shieldInput() {
    const window = root.Window.window;
    if (!active || !captureInput || window === null)
      return;
    const focused = window.activeFocusItem;
    if (focused !== null && focused !== root) {
      previousFocus = focused;
      root.forceActiveFocus();
    }
  }

  onActiveChanged: Qt.callLater(() => {
    if (active) {
      shieldInput();
    } else {
      const previous = previousFocus;
      previousFocus = null;
      if (captureInput && previous !== null && previous.enabled)
        previous.forceActiveFocus();
    }
  })
  onCaptureInputChanged: Qt.callLater(shieldInput)

  Connections {
    target: root.Window.window
    function onActiveFocusItemChanged() { root.shieldInput(); }
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Escape)
      root.dismissed();
    event.accepted = true;
  }
  Keys.onReleased: event => event.accepted = true
  MouseArea {
    anchors.fill: parent
    onWheel: event => event.accepted = true
  }
}
