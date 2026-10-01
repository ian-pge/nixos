import QtQuick
import QtTest
import Quickshell

ShellRoot {
  id: fixture
  property string stage: ""
  Window { id: window; visible: true; width: 100; height: 100; color: "black" }
  TestResult { id: results }
  TestCase {
    name: "Icon"
    when: window.visible
    function make(properties) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../ui/Icon.qml");
      compare(component.status, Component.Ready, component.errorString());
      const icon = createTemporaryObject(component, window.contentItem, properties);
      verify(icon !== null); return icon;
    }
    function test_svg_pixels_follow_color_size_and_stroke() {
      const icon = make({name: "x", size: 48, color: "#ff0000", strokeWidth: 2});
      fixture.stage = "load red icon";
      tryCompare(icon, "status", Image.Ready);
      fixture.stage = "geometry " + icon.width + "x" + icon.height;
      compare(icon.width, 48); compare(icon.height, 48);
      fixture.stage = "render red icon";
      wait(30);
      let rendered = grabImage(icon);
      fixture.stage = "red pixels " + rendered.pixel(rendered.width / 2, rendered.height / 2) + " size " + rendered.width + "x" + rendered.height;
      verify(rendered.red(rendered.width / 2, rendered.height / 2) > 200);
      compare(rendered.green(rendered.width / 2, rendered.height / 2), 0);
      icon.color = "#00ff00"; icon.size = 24; icon.strokeWidth = 3;
      fixture.stage = "load green icon";
      tryCompare(icon, "status", Image.Ready); wait(30);
      rendered = grabImage(icon);
      fixture.stage = "green pixels " + rendered.pixel(rendered.width / 2, rendered.height / 2);
      compare(icon.width, 24); verify(rendered.green(rendered.width / 2, rendered.height / 2) > 200);
      compare(rendered.red(rendered.width / 2, rendered.height / 2), 0);
    }
    function test_state_switch_keeps_bounds_and_loading_stops_when_hidden() {
      const icon = make({name: "loader-circle", spinning: true, size: 20});
      tryCompare(icon, "status", Image.Ready);
      const image = icon.children[0];
      tryVerify(() => image.rotation > 0);
      icon.visible = false; tryCompare(image, "rotation", 0);
      icon.spinning = false; icon.name = "wifi"; icon.visible = true;
      tryCompare(icon, "status", Image.Ready); compare(image.rotation, 0);
      compare(icon.width, 20); compare(icon.height, 20);
    }
    function test_entire_catalog_is_available_offline() {
      for (const name of ["bluetooth-connected", "wifi-low", "mic-off", "bell-off", "send", "file", "cloud-snow", "gpu", "headphones", "circle-question-mark"]) {
        const icon = make({name: name});
        verify(icon.valid, name); tryCompare(icon, "status", Image.Ready);
        icon.destroy();
      }
    }
    function cleanup() { if (results.failed) console.error("FAILED", qtest_results.functionName, fixture.stage); }
    function cleanupTestCase() {
      console.log("Icon: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.callLater(() => Qt.exit(results.failCount ? 1 : 0));
    }
  }
}
