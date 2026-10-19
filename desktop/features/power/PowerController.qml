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
  readonly property var laptopBattery: batteryReading("Laptop", battery?.isPresent === true,
    battery?.ready ? battery.percentage : null,
    battery?.isPresent && battery.ready ? !onBattery
      && battery.state !== UPowerDeviceState.Discharging
      && battery.state !== UPowerDeviceState.PendingDischarge : null, 1)
  readonly property bool batteryAvailable: laptopBattery.available
  readonly property bool batteryPluggedIn: laptopBattery.pluggedIn === true
  readonly property var batteryPercent: laptopBattery.percent
  readonly property var keyboardBatteries: bluetoothDevices
    .filter(device => device.icon === "input-keyboard")
    .slice().sort((left, right) => left.address.localeCompare(right.address))
    .map(device => batteryReading(device.name || device.deviceName || "Keyboard", device.connected,
      device.connected && device.batteryAvailable ? device.battery : null, keyboardPluggedIn(device), 1))
    .filter(device => device.available)
  readonly property var mouseBatteries: bluetoothDevices
    .filter(device => device.icon === "input-mouse")
    .slice().sort((left, right) => left.address.localeCompare(right.address))
    .map(device => {
      const power = mousePowerDevice(device);
      const pluggedIn = mouseExternalPower(power, device.connected);
      const level = device.connected && device.batteryAvailable && percent(device.battery, 1) !== null ? device.battery
        : power && power.state !== UPowerDeviceState.Unknown ? power.percentage : null;
      return batteryReading(device.name || device.deviceName || "Mouse", device.connected, level, pluggedIn, 1);
    }).filter(device => device.available)
  // BlueZ currently exposes a single level for Pixel Buds, not left/right/case.
  // Keep a connected device visible while its first battery report is pending.
  readonly property var earbudBatteries: bluetoothDevices
    .filter(device => device.connected && (/pixel\s+buds/i.test(device.deviceName || "")
      || /pixel\s+buds/i.test(device.name || "")))
    .slice().sort((left, right) => left.address.localeCompare(right.address))
    .map(device => batteryReading(device.name || device.deviceName || "Pixel Buds", device.connected,
      device.batteryAvailable ? device.battery : null, bluetoothPower(device), 1))
  // Use the reported Bluetooth level as-is (the Pixel's hands-free profile
  // reports 20% steps). USB presence is independent from that battery report.
  readonly property var phoneBatteries: bluetoothDevices
    .filter(device => device.icon === "phone")
    .slice().sort((left, right) => left.address.localeCompare(right.address))
    .map(device => batteryReading(device.name || device.deviceName || "Phone", device.connected,
      device.connected && device.batteryAvailable ? device.battery : null, phonePluggedIn(device), 1, 40))
    .filter(device => device.available)
  readonly property var accessoryBatteries: keyboardBatteries.concat(mouseBatteries, earbudBatteries, phoneBatteries)
  readonly property var batteries: (batteryAvailable ? [laptopBattery] : []).concat(accessoryBatteries)

  // Every source uses the same visibility and unknown-value rules. A missing
  // percentage is not zero; a missing power report is not "unplugged".
  function percent(value, maximum = 100) {
    return typeof value === "number" && isFinite(value) && value >= 0 && value <= maximum
      ? Math.round(value * 100 / maximum) : null;
  }

  function batteryReading(name, connected, level, pluggedIn, maximum = 100, lowThreshold = 20) {
    const available = connected === true || pluggedIn === true;
    return {
      name: name,
      available: available,
      percent: available ? percent(level, maximum) : null,
      lowThreshold: lowThreshold,
      pluggedIn: available && typeof pluggedIn === "boolean" ? pluggedIn : null
    };
  }

  function externalPower(power) {
    if (!power?.ready || !power.isPresent) return null;
    switch (power.state) {
      case UPowerDeviceState.Charging:
      case UPowerDeviceState.PendingCharge: return true;
      // UPower can infer "full" from 100%, even for a discharging peripheral.
      case UPowerDeviceState.FullyCharged: return null;
      case UPowerDeviceState.Discharging:
      case UPowerDeviceState.PendingDischarge:
      case UPowerDeviceState.Empty: return false;
      default: return null;
    }
  }

  function mouseExternalPower(power, connected) {
    if (!power?.ready || !power.isPresent) return null;
    const hidpp = power.type === UPowerDeviceType.Mouse && /^hidpp_battery_/.test(power.nativePath || "");
    if (!connected && !hidpp) return null;
    // The kernel HID++ status distinguishes "charge complete" from 100% on
    // battery. UPower loses this distinction; use the existing fresh telemetry.
    if (hidpp && telemetry?.systemFresh) {
      const raw = (telemetry.hidppBatteries ?? []).find(reading => reading.nativePath === power.nativePath);
      if (raw) {
        if (raw.status === "Charging" || raw.status === "Full") return true;
        if (raw.status === "Discharging") return false;
        return null;
      }
    }
    return externalPower(power);
  }
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

  function bluetoothPower(device) {
    if (!device.connected) return null;
    const power = powerDevices.find(item => item.ready && item.isPresent && item.nativePath === device.dbusPath);
    return externalPower(power);
  }

  function keyboardPluggedIn(device) {
    // Agar BLE only reports a percentage. Keep the known USB identity precise,
    // independent of its port, and never use a stale system-device snapshot.
    if (device.address === "E6:9D:03:3D:7C:3C" && !!telemetry?.systemFresh
      && telemetry.usbDevices.some(usb => usb.vendorId === "9d5b"
        && usb.productId === "2565" && usb.serial === "0D37F50E477AF37B")) return true;
    return bluetoothPower(device);
  }

  function phonePluggedIn(device) {
    // Match this Pixel, not another Google phone. Its USB product ID changes
    // between charging/MTP/ADB modes; vendor + serial remain the same.
    // This confirms attachment to this PC, not that charging is in progress.
    if (device.address !== "94:45:60:3C:A5:14" || !telemetry?.systemFresh) return null;
    return telemetry.usbDevices.some(usb => usb.vendorId === "18d1" && usb.serial === "38051FDJG003S6");
  }
}
