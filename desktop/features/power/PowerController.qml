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
    && battery.state !== UPowerDeviceState.Discharging
    && battery.state !== UPowerDeviceState.PendingDischarge
  readonly property int batteryPercent: batteryAvailable ? Math.round(battery.percentage * 100) : 0
  readonly property var keyboardBatteries: bluetoothDevices
    .filter(device => device.icon === "input-keyboard")
    .slice().sort((left, right) => left.address.localeCompare(right.address))
    .map(device => ({
      available: device.connected && device.batteryAvailable,
      percent: device.connected && device.batteryAvailable ? Math.round(device.battery * 100) : null,
      pluggedIn: keyboardPluggedIn(device)
    })).filter(device => device.available || device.pluggedIn)
  // BlueZ currently exposes a single level for Pixel Buds, not left/right/case.
  // Keep a connected device visible while its first battery report is pending.
  readonly property var earbudBatteries: bluetoothDevices
    .filter(device => device.connected && (/pixel\s+buds/i.test(device.deviceName || "")
      || /pixel\s+buds/i.test(device.name || "")))
    .slice().sort((left, right) => left.address.localeCompare(right.address))
    .map(device => ({
      address: device.address,
      name: device.name || device.deviceName || "Pixel Buds",
      percent: device.batteryAvailable && typeof device.battery === "number" && isFinite(device.battery)
        ? Math.round(Math.max(0, Math.min(1, device.battery)) * 100) : null,
      pluggedIn: bluetoothCharging(device)
    }))
  readonly property var accessoryBatteries: keyboardBatteries.concat(earbudBatteries)

  function bluetoothCharging(device) {
    const power = powerDevices.find(item => item.ready && item.isPresent && item.nativePath === device.dbusPath);
    return !!power && (power.state === UPowerDeviceState.Charging || power.state === UPowerDeviceState.PendingCharge);
  }

  function keyboardPluggedIn(device) {
    if (bluetoothCharging(device)) return true;
    // Agar BLE only reports a percentage. Keep the known USB identity precise,
    // independent of its port, and never use a stale system-device snapshot.
    return device.address === "E6:9D:03:3D:7C:3C" && !!telemetry?.systemFresh
      && telemetry.usbDevices.some(usb => usb.vendorId === "9d5b"
        && usb.productId === "2565" && usb.serial === "0D37F50E477AF37B");
  }
}
