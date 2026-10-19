import QtQuick
import "../ui/Theme.js" as Theme

// One visual policy for every battery, regardless of its data provider.
BarDial {
  property bool pluggedIn: false
  property real lowThreshold: 20
  charging: pluggedIn
  accent: pluggedIn ? Theme.batteryPluggedIn
    : known && value < lowThreshold ? Theme.error : Theme.sideBattery
  accessibleText: label + " · " + (known ? Math.round(value) + "%" : "Unavailable")
    + (pluggedIn ? " · Powered" : "")
}
