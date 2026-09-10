import Quickshell
import QtQuick
import QtTest

ShellRoot {
  Window {
    id: testWindow
    visible: true
    width: 600
    height: 250
    readonly property var popup: popupLoader.item

    QtObject {
      id: message
      property string appName: "Beeper"
      property string summary: "Camille"
      property string body: "Salut !"
      property string image: ""
      property string appIcon: ""
    }
    QtObject {
      id: notificationState
      property var presented: message
      function activate() {
      }
    }
    Loader {
      id: popupLoader
      Component.onCompleted: setSource("file://" + Quickshell.shellDir + "/../components/NotificationPopup.qml", {
        notificationData: notificationState,
        maximumWidth: 434
      })
      onLoaded: {
        const loadedPopup = item as Item;
        loadedPopup.width = Qt.binding(() => Math.min(loadedPopup.implicitWidth, 434));
        loadedPopup.height = Qt.binding(() => loadedPopup.implicitHeight);
      }
      onStatusChanged: if (status === Loader.Error) Qt.exit(1)
    }

    TestResult {
      id: results
    }

    TestCase {
      name: "NotificationPopup"
      readonly property var popup: testWindow.popup
      when: testWindow.visible && testWindow.popup !== null

      function cleanupTestCase() {
        // qs hosts the static Quickshell plugins, but not QtTest's CLI reporter.
        console.log("NotificationPopup: " + results.passCount + " passed, " + results.failCount + " failed");
        Qt.exit(results.failCount > 0 ? 1 : 0);
      }

      function cleanup() {
        if (results.failed)
          console.error("FAILED", qtest_results.functionName, qtest_results.dataTag, "geometry", popup.implicitWidth, popup.width, popup.height);
      }

      function init() {
        notificationState.presented = message;
        message.appName = "Beeper";
        message.summary = "Camille";
        message.body = "Salut !";
        popup.width = Qt.binding(() => Math.min(popup.implicitWidth, 434));
        wait(0);
      }

      function test_shortMessageIsCompact() {
        compare(popup.implicitWidth, 160);
        compare(popup.width, 160);
        compare(popup.height, 80);
      }

      function test_eachTextFieldCanSetWidth_data() {
        return [
          {
            tag: "application",
            field: "appName"
          },
          {
            tag: "title",
            field: "summary"
          },
          {
            tag: "message",
            field: "body"
          }
        ];
      }

      function test_eachTextFieldCanSetWidth(row) {
        message[row.field] = "W".repeat(20);
        verify(popup.implicitWidth > 160);
        verify(popup.implicitWidth < 480);
        const wider = popup.implicitWidth;
        message[row.field] = "i".repeat(20);
        verify(popup.implicitWidth < wider, "Use actual glyph widths, not character count");
      }

      function test_multilineUsesLongestLine_data() {
        return [
          {
            tag: "LF",
            separator: "\n"
          },
          {
            tag: "CRLF",
            separator: "\r\n"
          },
          {
            tag: "CR",
            separator: "\r"
          },
          {
            tag: "line separator",
            separator: "\u2028"
          },
          {
            tag: "paragraph separator",
            separator: "\u2029"
          }
        ];
      }

      function test_multilineUsesLongestLine(row) {
        const line = "On se retrouve ce soir ?";
        message.body = line;
        const oneLineWidth = popup.implicitWidth;
        message.body = "Oui" + row.separator + line + row.separator + "OK";
        compare(popup.implicitWidth, oneLineWidth);
        message.body = line + row.separator + line;
        compare(popup.implicitWidth, oneLineWidth);
      }

      function test_longMessageRespectsCaps() {
        message.body = "Un long message avec du texte à renvoyer à la ligne. ".repeat(30);
        compare(popup.implicitWidth, 480);
        compare(popup.width, 434);
        tryVerify(() => popup.height > 80 && popup.height <= 180);
        message.body = "https://example.org/" + "a".repeat(600);
        compare(popup.implicitWidth, 480);
        compare(popup.width, 434);
      }

      function test_measurementDoesNotDependOnAnimatedWidth() {
        message.body = "Message de taille intermédiaire";
        const naturalWidth = popup.implicitWidth;
        wait(50);
        const finalHeight = popup.implicitHeight;
        popup.width = 180;
        wait(50);
        compare(popup.implicitWidth, naturalWidth);
        compare(popup.implicitHeight, finalHeight);
        popup.width = 434;
        wait(50);
        compare(popup.implicitWidth, naturalWidth);
        compare(popup.implicitHeight, finalHeight);
      }

      function test_replacementShrinksAgain() {
        message.body = "Un très long message. ".repeat(30);
        compare(popup.implicitWidth, 480);
        message.body = "OK";
        compare(popup.implicitWidth, 160);
        tryCompare(popup, "height", 80);
      }

      function test_unicodeRemainsFinite_data() {
        return [
          {
            tag: "emoji",
            text: "👩🏽‍💻 Salut 👋"
          },
          {
            tag: "RTL",
            text: "مرحبا كيف حالك اليوم؟"
          },
          {
            tag: "CJK",
            text: "你好，今天晚上有空吗？"
          },
          {
            tag: "combining",
            text: "Cafe\u0301, de\u0301ja\u0300 arrive\u0301."
          }
        ];
      }

      function test_unicodeRemainsFinite(row) {
        message.body = row.text;
        verify(isFinite(popup.implicitWidth));
        verify(popup.implicitWidth >= 160 && popup.implicitWidth <= 480);
      }

      function test_emptyNotificationStaysWellFormed() {
        notificationState.presented = null;
        compare(popup.implicitWidth, 160);
        tryCompare(popup, "height", 80);
      }
    }
  }
}
