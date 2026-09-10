import Quickshell
import QtQuick
import QtTest

ShellRoot {
  id: root
  property var weather: null
  Component.onCompleted: {
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../WeatherData.qml");
    if (component.status !== Component.Ready) {
      console.error(component.errorString()); Qt.exit(1); return;
    }
    weather = component.createObject(root, {autoRefresh: false});
  }
  TestResult { id: results }
  TestCase {
    name: "WeatherData"
    when: root.weather !== null
    function cleanupTestCase() {
      console.log("WeatherData: " + results.passCount + " passed, " + results.failCount + " failed");
      Qt.exit(results.failCount > 0 ? 1 : 0);
    }
    function cleanup() {
      if (results.failed) console.error("FAILED", qtest_results.functionName);
    }
    function init() {
      root.weather.snapshot = null;
      root.weather.lastError = "";
      root.weather.reportedStale = false;
    }
    function report(age = 0, temperature = 0) {
      return {data: {version: 2, updatedAt: Math.floor(Date.now() / 1000) - age,
        location: {name: "Paris"}, timezone: "Europe/Paris", temperatureC: temperature,
        days: {"2026-09-10": {code: 0, temperatureMinC: 0, temperatureMaxC: 12.5}}}, stale: false, error: null};
    }
    function test_zero_and_null_temperature() {
      root.weather.applyReport(JSON.stringify(report()));
      compare(root.weather.temperatureText, "0°");
      compare(root.weather.days["2026-09-10"].code, 0);
      compare(root.weather.days["2026-09-10"].temperatureMinC, 0);
      compare(root.weather.days["2026-09-10"].temperatureMaxC, 12.5);
      root.weather.applyReport(JSON.stringify(report(0, null)));
      compare(root.weather.temperatureText, "--°");
      verify(root.weather.usable);
    }
    function test_age_limits() {
      root.weather.applyReport(JSON.stringify(report(4000)));
      verify(root.weather.usable); verify(root.weather.stale);
      root.weather.applyReport(JSON.stringify(report(87000)));
      verify(!root.weather.usable);
      compare(root.weather.temperatureText, "--°");
      compare(Object.keys(root.weather.days).length, 0);
    }
    function test_offline_retains_recent_snapshot() {
      root.weather.applyReport(JSON.stringify(report()));
      root.weather.applyReport(JSON.stringify({data: null, stale: true, error: "Météo indisponible"}));
      verify(root.weather.usable); verify(root.weather.stale);
      compare(root.weather.locationText, "Paris");
      verify(root.weather.updateText.startsWith("Cache "));
    }
    function test_malformed_does_not_replace_valid_snapshot() {
      root.weather.applyReport(JSON.stringify(report()));
      root.weather.applyReport("{}");
      compare(root.weather.locationText, "Paris");
      compare(root.weather.lastError, "Météo indisponible");
    }
    function test_previous_protocol_cannot_replace_snapshot() {
      root.weather.applyReport(JSON.stringify(report()));
      const old = report();
      old.data.version = 1;
      old.data.days = {"2026-09-10": 95};
      root.weather.applyReport(JSON.stringify(old));
      compare(root.weather.days["2026-09-10"].code, 0);
      compare(root.weather.lastError, "Météo indisponible");
    }
  }
}
