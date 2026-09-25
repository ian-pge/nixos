import Quickshell
import QtQuick

// Compile the actual integration graph without instantiating desktop services.
// Run with the packaged Quickshell (Qt Multimedia + Liquid Glass), offscreen,
// and a private D-Bus session. No real account, microphone or message is used.
ShellRoot {
  Component.onCompleted: {
    let failures = 0;
    for (const name of ["../BeeperData.qml", "../components/BeeperPanel.qml",
        "../NotificationData.qml", "../StatusData.qml", "../Bar.qml"]) {
      const component = Qt.createComponent("file://" + Quickshell.shellDir + "/" + name);
      if (component.status !== Component.Ready) {
        console.error(name + ": " + component.errorString());
        failures++;
      }
    }
    console.log("Messenger integration: " + (failures ? failures + " component failures" : "all components compile"));
    Qt.callLater(() => Qt.exit(failures ? 1 : 0));
  }
}
