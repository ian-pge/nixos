import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import QtQuick

Scope {
  id: root
  property bool enabled: true
  property var telemetry: null
  property var battery: enabled ? UPower.displayDevice : null
  property bool onBattery: enabled ? UPower.onBattery : true
  property var powerDevices: enabled ? UPower.devices.values : []
  property var bluetoothDevices: enabled ? Bluetooth.devices.values : []
  readonly property bool batteryAvailable: battery !== null && battery.ready && battery.isPresent
  readonly property bool batteryPluggedIn: batteryAvailable && !onBattery
  readonly property int batteryPercent: batteryAvailable ? Math.round(battery.percentage * 100) : 0
  readonly property var keyboardBatteries: bluetoothDevices
    .filter(device => device.icon === "input-keyboard")
    .slice().sort((left, right) => left.address.localeCompare(right.address))
    .map(device => ({
      available: device.connected && device.batteryAvailable,
      percent: device.connected && device.batteryAvailable ? Math.round(device.battery * 100) : null,
      pluggedIn: keyboardPluggedIn(device)
    })).filter(device => device.available || device.pluggedIn)

  function keyboardPluggedIn(device) {
    const power = powerDevices.find(item => item.ready && item.isPresent && item.nativePath === device.dbusPath);
    if (power && (power.state === UPowerDeviceState.Charging || power.state === UPowerDeviceState.PendingCharge))
      return true;
    // Agar BLE only reports a percentage. Keep the known USB identity precise,
    // independent of its port, and never use a stale system-device snapshot.
    return device.address === "E6:9D:03:3D:7C:3C" && !!telemetry?.systemFresh
      && telemetry.usbDevices.some(usb => usb.vendorId === "9d5b"
        && usb.productId === "2565" && usb.serial === "0D37F50E477AF37B");
  }
}
