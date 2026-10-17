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
  readonly property var mouseBatteries: bluetoothDevices
    .filter(device => device.icon === "input-mouse")
    .slice().sort((left, right) => left.address.localeCompare(right.address))
    .map(device => {
      const power = mousePowerDevice(device);
      const pluggedIn = !!power && (power.state === UPowerDeviceState.Charging || power.state === UPowerDeviceState.PendingCharge);
      const connected = device.connected || pluggedIn;
      const level = device.connected && device.batteryAvailable && validLevel(device.battery) ? device.battery
        : power && power.state !== UPowerDeviceState.Unknown && validLevel(power.percentage) ? power.percentage : null;
      return {
        name: device.name || device.deviceName || "Mouse",
        available: connected && level !== null,
        percent: connected && level !== null ? Math.round(Math.max(0, Math.min(1, level)) * 100) : null,
        pluggedIn: pluggedIn
      };
    }).filter(device => device.available || device.pluggedIn)
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
  readonly property var accessoryBatteries: keyboardBatteries.concat(mouseBatteries, earbudBatteries)

  function validLevel(value) { return typeof value === "number" && isFinite(value); }
  function mousePowerDevice(device) {
    const present = powerDevices.filter(item => item.ready && item.isPresent);
    const direct = device.dbusPath && present.find(item => item.nativePath === device.dbusPath);
    if (direct) return direct;
    // Logitech HID++ uses a kernel nativePath instead of the BlueZ path.
    // UPower's QML API exposes the model, but not the serial/address: only
    // accept an unambiguous model match, never another mouse's charge state.
    const normalize = value => String(value || "").trim().toLowerCase();
    const model = normalize(device.deviceName || device.name);
    if (!model || bluetoothDevices.filter(other => other.icon === "input-mouse"
        && normalize(other.deviceName || other.name) === model).length !== 1) return null;
    const matches = present.filter(item => item.type === UPowerDeviceType.Mouse && normalize(item.model) === model);
    return matches.length === 1 ? matches[0] : null;
  }

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
