import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Local.LiquidGlass

ShellRoot {
    id: root
    property bool showGlass: true
    property bool probeVisible: false
    property int probeFrames: 0
    IpcHandler {
        target: "glass-scene"
        function freeze(): void { movement.stop(); movingBand.x = 600; }
        function traffic(active: bool): void { root.showGlass = !active; root.probeVisible = active; }
        function ticks(): int { return root.probeFrames; }
    }
    Window {
        visible: true
        visibility: Window.FullScreen
        color: "#121827"
        title: "Glass test background"
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#122639" }
                GradientStop { position: 1; color: "#bbd4dc" }
            }
            Repeater {
                model: 70
                Rectangle {
                    required property int index
                    x: index * 40
                    y: 0
                    width: 4
                    height: parent.height
                    color: "#b7e7e9"
                }
            }
            Repeater {
                model: 40
                Rectangle {
                    required property int index
                    y: index * 40
                    height: 3; width: parent.width
                    color: "#739faa"
                }
            }
            Rectangle {
                id: movingBand
                width: 110; height: parent.height
                color: "#ed647e"
                NumberAnimation on x { id: movement; from: -110; to: 1400; duration: 4500; loops: Animation.Infinite }
            }
        }
    }
    PanelWindow {
        visible: root.showGlass
        anchors { top: true; left: true; right: true }
        implicitHeight: 760
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "liquid-glass-test"
        exclusiveZone: 0
        // A deep interior catches regressions hidden by the small capsules:
        // the old fixed-range distance field never reached this panel's core.
        Rectangle {
            id: deepGlass
            x: 35; y: 300; width: 420; height: 440
            radius: 18
            GlassShape { anchors.fill: parent; radius: deepGlass.radius }
            color: "#26181926"
            Text {
                anchors.centerIn: parent
                text: "Courbure intérieure"
                color: "#ffffff"; font.pixelSize: 19
            }
        }
        Row {
            x: 35; y: 30; spacing: 25
            Repeater {
                model: 3
                Rectangle {
                    id: capsule
                    required property int index
                    width: index === 1 ? 420 : 200
                    height: index === 1 ? 190 : 50
                    radius: index === 1 ? 18 : 25
                    GlassShape { anchors.fill: parent; radius: capsule.radius }
                    color: "#26181926"
                    Text {
                        anchors.centerIn: parent
                        text: ["Wi-Fi  󰤨", "Liquid Glass\nFenêtre animée en direct", "Volume  65 %"][index]
                        color: "#ffffff"; font.pixelSize: 19
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }
    // An unrelated small animated surface, far from the remaining real Pill.
    PanelWindow {
        visible: root.probeVisible
        anchors { left: true; bottom: true }
        margins { left: 30; bottom: 20 }
        implicitWidth: 160; implicitHeight: 60
        exclusiveZone: 0
        color: "#102030"
        WlrLayershell.namespace: "liquid-glass-damage-probe"
        WlrLayershell.layer: WlrLayer.Overlay
        Rectangle {
            width: 20; height: 60; color: "#ff9933"
            onXChanged: root.probeFrames++
            NumberAnimation on x { from: 0; to: 140; duration: 700; loops: Animation.Infinite; running: root.probeVisible }
        }
    }
}
