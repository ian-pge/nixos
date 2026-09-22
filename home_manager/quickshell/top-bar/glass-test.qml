import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

// Only invoked by tools/liquid-glass/tests/nested.mjs in its private compositor.
// The normal shell.qml never creates this fixture.
ShellRoot {
  id: fixture
  property int topInset: 250
  property int rightInset: 40
  property int capsuleWidth: 260
  property bool activated: false
  Component.onCompleted: {
    if (Quickshell.env("LIQUID_GLASS_TEST") !== "1") { Qt.exit(1); return; }
    // Compile the real bar on a Wayland backend without creating its services.
    const bar = Qt.createComponent("file://" + Quickshell.shellDir + "/Bar.qml");
    if (bar.status !== Component.Ready) { console.error(bar.errorString()); Qt.exit(1); }
  }
  IpcHandler {
    target: "glass-test"
    function enabled(): bool { return GlassState.enabled; }
    function activate(value: bool): void { fixture.activated = value; }
    function geometry(top: int, right: int, width: int): void {
      fixture.topInset = top; fixture.rightInset = right; fixture.capsuleWidth = width;
    }
  }
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; right: true }
      margins { top: fixture.topInset; right: fixture.rightInset }
      implicitWidth: fixture.capsuleWidth
      implicitHeight: 36
      exclusiveZone: 0
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-top-bar"
      Pill { anchors.fill: parent; text: "Capsule Quickshell réelle"; accent: "#cad3f5"; forceHovered: fixture.activated }
    }
  }
}
