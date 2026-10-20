import QtQuick
import Quickshell

// Explicit opt-in hardware check of the production controller + packaged helper.
// Not included in the offline regression runner. Never starts the desktop shell.
ShellRoot {
  id: fixture
  property var power: null
  property bool finished: false
  property int soakMs: Number(Quickshell.env("BATTERY_RELAY_SOAK_MS") || "0")
  property bool requireFitbit: Quickshell.env("BATTERY_RELAY_REQUIRE_FITBIT") === "1"
  property real stableSince: 0
  property real lastPhoneTimestamp: 0
  property int phoneSamples: 0
  function inspect() {
    if (finished || power === null) return;
    if (power.phoneBatteries.length !== 1) {
      if (stableSince > 0) console.log("Battery Relay live: connection lost; waiting for automatic recovery");
      stableSince = 0; phoneSamples = 0; lastPhoneTimestamp = 0;
      return;
    }
    const sample = power.phoneBatteries[0];
    if (sample.percent === null) return;
    if (!stableSince) {
      stableSince = Date.now();
      console.log("Battery Relay live reading: " + JSON.stringify(sample));
    }
    if (power.phoneRelay.updatedAt !== lastPhoneTimestamp) {
      lastPhoneTimestamp = power.phoneRelay.updatedAt; phoneSamples++;
    }
    if (Date.now() - stableSince < soakMs || (soakMs > 0 && phoneSamples < 4)
        || (requireFitbit && power.fitbitBatteries.length !== 1)) return;
    finished = true;
    console.log("Battery Relay live: " + JSON.stringify({stableMs: Date.now() - stableSince,
      phoneSamples, phone: sample, fitbit: power.fitbitBatteries}));
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
    power.fitbitBatteriesChanged.connect(inspect);
    power.enabled = true;
  }
  Timer {
    running: fixture.soakMs > 0; repeat: true; interval: 15000
    onTriggered: {
      fixture.inspect();
      if (!fixture.finished && fixture.power !== null)
        console.log("Battery Relay live progress: " + JSON.stringify({
          connected: fixture.power.phoneRelay.connected, phoneSamples: fixture.phoneSamples,
          stableMs: fixture.stableSince ? Date.now() - fixture.stableSince : 0,
          fitbitAvailable: fixture.power.phoneRelay.fitbitAvailable}));
    }
  }
  Timer {
    running: true; interval: fixture.soakMs > 0 ? fixture.soakMs + 240000 : 45000
    onTriggered: { console.error("Battery Relay live test timed out"); Qt.exit(1); }
  }
}
