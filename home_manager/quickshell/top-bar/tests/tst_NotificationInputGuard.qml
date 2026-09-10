import QtQuick
import QtTest
import "../components"

Item {
  width: 400
  height: 200

  TextInput {
    id: first
    property int escapeCount: 0
    text: "before"
    Keys.onEscapePressed: escapeCount++
  }
  TextInput { id: second; y: 40 }
  NotificationInputGuard {
    id: guard
    anchors.fill: parent
    active: false
    captureInput: true
    onDismissed: active = false
  }

  TestCase {
    name: "NotificationInputGuard"
    when: windowShown

    function init() {
      guard.active = false;
      guard.captureInput = true;
      wait(0);
      first.text = "before";
      first.escapeCount = 0;
      first.cursorPosition = first.text.length;
      first.forceActiveFocus();
      tryCompare(first, "activeFocus", true);
    }

    function test_preservesInputAndEscape() {
      guard.active = true;
      tryCompare(guard, "activeFocus", true);
      keyClick(Qt.Key_X);
      compare(first.text, "before");
      keyClick(Qt.Key_Escape);
      tryCompare(first, "activeFocus", true);
      compare(first.escapeCount, 0);
      compare(first.text, "before");
      keyClick(Qt.Key_X);
      compare(first.text, "beforex");
    }

    function test_keepsOrdinaryApplicationFocus() {
      guard.captureInput = false;
      guard.active = true;
      wait(0);
      verify(first.activeFocus);
      keyClick(Qt.Key_X);
      compare(first.text, "beforex");
    }

    function test_restoresLatestUnderlyingField() {
      guard.active = true;
      tryCompare(guard, "activeFocus", true);
      second.forceActiveFocus();
      tryCompare(guard, "activeFocus", true);
      compare(guard.previousFocus, second);
      guard.active = false;
      tryCompare(second, "activeFocus", true);
    }
  }
}
