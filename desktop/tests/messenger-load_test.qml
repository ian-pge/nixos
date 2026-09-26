import Quickshell
import QtQuick

// Compile the actual integration graph without instantiating desktop services.
// Run with the packaged Quickshell (Qt Multimedia + Liquid Glass), offscreen,
// and a private D-Bus session. No real account, microphone or message is used.
ShellRoot {
  Component.onCompleted: {
    let failures = 0;
    for (const name of ["../features/messenger/BeeperData.qml", "../features/messenger/BeeperPanel.qml", "../shell/BeeperBubble.qml",
        "../shell/MessengerController.qml", "../shell/GlassController.qml", "../shell/ShellCoordinator.qml", "../shell.qml",
        "../shell/MessengerHost.qml",
        "../features/notifications/NotificationData.qml", "../bar/CentralCapsule.qml", "../bar/Bar.qml"]) {
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
