import QtQuick
import QtTest
import Quickshell

// Run with messenger-wayland_test.mjs --avatar for the normal scene graph.
// Only a local synthetic image is rendered; no account or service is started.
ShellRoot {
  id: fixture
  property var avatar: null
  readonly property string picture: "data:image/svg+xml," + encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="#ff0000"/></svg>')
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/messenger/BeeperAvatar.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.callLater(() => Qt.exit(1)); return; }
    avatar = component.createObject(testWindow.contentItem, {x: 10, y: 10, diameter: 64});
  }
  Window { id: testWindow; width: 100; height: 100; visible: true; color: "#101010" }
  TestResult { id: results }
  TestCase {
    name: "BeeperAvatar"
    when: fixture.avatar !== null && testWindow.visible
    function cleanupTestCase() {
      console.log("BeeperAvatar: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName); }
    function test_photo_is_clipped_to_circle_and_badge_stays_visible() {
      verify(Quickshell.env("QT_QUICK_BACKEND") !== "software", "Use the normal scene graph for the clipping test");
      avatar.chat = {id: "contact", type: "single", title: "Contact", network: "WhatsApp", imgURL: fixture.picture};
      tryCompare(avatar, "imageReady", true);
      verify(waitForRendering(avatar));
      const image = grabImage(avatar);
      compare(image.red(image.width / 2, image.height / 2), 255);
      compare(image.green(image.width / 2, image.height / 2), 0);
      compare(image.pixel(2, 2), "#101010", "The window background must show through the photograph's corners");
      compare(image.pixel(image.width - 3, 2), "#101010");
      compare(image.pixel(2, image.height - 3), "#101010");
      const badge = findChild(avatar, "beeperNetworkBadge");
      verify(badge.visible);
      const scale = image.width / avatar.width;
      const point = badge.mapToItem(avatar, 3, badge.height / 2);
      const x = Math.floor(point.x * scale), y = Math.floor(point.y * scale);
      verify(image.green(x, y) > image.red(x, y), "WhatsApp badge must be rendered above the photograph");
    }
    function test_contact_fallback_and_network_update() {
      avatar.chat = {id: "contact", type: "single", title: "Contact", network: "Telegram", participants: {items: [
        {isSelf: true, imgURL: "file:///unused-self-image"}, {isSelf: false, imgURL: fixture.picture}
      ]}};
      tryCompare(avatar, "imageReady", true);
      compare(avatar.avatarSource, fixture.picture);
      compare(avatar.network.key, "telegram");
      avatar.chat = {id: "group", type: "group", title: "Groupe", network: "Telegram", participants: {items: [{isSelf: false, imgURL: fixture.picture}]}};
      compare(avatar.avatarSource, "");
      tryCompare(avatar, "imageReady", false);
      verify(findChild(avatar, "beeperNetworkBadge").visible);
      avatar.chat = null;
      verify(!findChild(avatar, "beeperNetworkBadge").visible);
    }
  }
}
