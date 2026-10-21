pragma ComponentBehavior: Bound
import QtQuick
import "../ui/Theme.js" as Theme

Item {
  id: root
  required property var reading
  property string dialName: "earbudBatteryPill"
  readonly property bool audioConnected: reading?.audioConnected === true
  implicitHeight: dial.implicitHeight
  // Connection state must never move neighbouring battery widgets.
  implicitWidth: dial.width

  BatteryDial {
    id: dial
    objectName: root.dialName
    iconName: "headphones"
    label: (root.reading?.name || "Pixel Buds") + " battery"
    value: root.reading?.percent ?? null
    pluggedIn: root.reading?.pluggedIn === true
    warning: root.reading?.warning === true
    tooltipOverride: (root.reading?.tooltip || "") + (root.audioConnected ? "\nAudio connecté au PC" : "")
    accessibleText: label + " · " + tooltipText.replace(/\n/g, " · ") + (pluggedIn ? " · Powered" : "")
  }
  DialBadge {
    id: badge
    objectName: "earbudAudioBadge"
    visible: root.audioConnected
    z: 2
    compact: true
    x: dial.width - width - Theme.barSize(3)
    y: Theme.barSize(2)
    iconName: "check"
    color: Theme.sideBattery
    Accessible.name: "Écouteurs connectés en audio au PC"
  }
}
