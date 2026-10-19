import QtQuick
import Quickshell

// Explicit opt-in hardware check of the production controller + packaged helper.
// Not included in the offline regression runner. Never starts the desktop shell.
ShellRoot {
  id: fixture
  property var power: null
  property bool finished: false
  function inspect() {
    if (finished || power === null || power.phoneBatteries.length !== 1) return;
    const sample = power.phoneBatteries[0];
    if (sample.percent === null) return;
    finished = true;
    console.log("Battery Relay live reading: " + JSON.stringify(sample));
    // Do not mutate the source while its phoneBatteries binding is evaluating.
    Qt.callLater(() => {
      power.enabled = false;
      if (power.phoneBatteries.length !== 0) { Qt.exit(1); return; }
      console.log("Battery Relay live: receipt and invalidation passed");
      Qt.callLater(() => Qt.exit(0));
    });
  }
  Component.onCompleted: {
    if (Quickshell.env("BATTERY_RELAY_LIVE_TEST") !== "1"
        || !Quickshell.env("BATTERY_RELAY_TEST_RECEIVER")) {
      console.error("This hardware test requires explicit opt-in and a receiver path.");
      Qt.exit(1); return;
    }
    const component = Qt.createComponent("file://" + Quickshell.shellDir + "/../features/power/PowerController.qml");
    if (component.status !== Component.Ready) { console.error(component.errorString()); Qt.exit(1); return; }
    power = component.createObject(fixture, {enabled: false});
    power.phoneRelay.command = [Quickshell.env("BATTERY_RELAY_TEST_RECEIVER")];
    if (!power.phoneRelay.configured) { Qt.exit(1); return; }
    power.phoneBatteriesChanged.connect(inspect);
    power.enabled = true;
  }
  Timer { running: true; interval: 45000; onTriggered: { console.error("Battery Relay live test timed out"); Qt.exit(1); } }
}
