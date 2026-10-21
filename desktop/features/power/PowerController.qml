import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import QtQuick

Scope {
  id: root
  property bool enabled: true
  property var telemetry: null
  property var audio: null
  property string earbudsBluetoothAddress: Quickshell.env("QS_EARBUDS_BLUETOOTH_ADDRESS") || ""
  property var battery: enabled ? UPower.displayDevice : null
  property bool onBattery: enabled ? UPower.onBattery : true
  property var powerDevices: enabled ? UPower.devices.values : []
  property var bluetoothDevices: enabled ? Bluetooth.devices.values : []
  property string phoneName: "Phone"
  readonly property var phoneRelay: relay
  BatteryRelayData { id: relay; enabled: root.enabled }
  readonly property var earbudsData: earbuds
  FastPairBatteryData { id: earbuds; enabled: root.enabled }
  readonly property bool earbudDataConnected: earbuds.available
  readonly property bool earbudAudioConnected: {
    const address = earbudsBluetoothAddress.toUpperCase();
    return /^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(address)
      && (audio?.bluetoothOutputAddresses ?? []).includes(address)
      && bluetoothDevices.some(device => device.connected === true
        && String(device.address || "").toUpperCase() === address);
  }
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
      const pluggedIn = mouseExternalPower(power, device);
      const level = device.connected && device.batteryAvailable && percent(device.battery, 1) !== null ? device.battery
        : power && power.state !== UPowerDeviceState.Unknown ? power.percentage : null;
      return batteryReading(device.name || device.deviceName || "Mouse", device.connected, level, pluggedIn, 1);
    }).filter(device => device.available)
  // Direct Fast Pair BATT is independent of phone and audio connections.
  // The dial always represents the case. A low bud warns even if it is full.
  readonly property var earbudBatteries: earbuds.available
    ? [earbudReading("Pixel Buds", earbuds.snapshot)] : []
  function earbudReading(name, values) {
    const text = value => value.percent === null ? "—" : value.percent + "%";
    return Object.assign(batteryReading(name, true, values.case.percent,
      values.case.charging === true ? true : null, 100, 20, values.case.charging), {
        audioConnected: root.earbudAudioConnected,
        warning: [values.case, values.left, values.right].some(value => value.percent !== null && value.percent < 20),
        tooltip: "Boîtier : " + text(values.case)
          + "\nGauche : " + text(values.left) + "\nDroite : " + text(values.right)
      });
  }
  // Battery Relay is the phone's only provider, including its power state.
  readonly property var phoneBatteries: relay.connected
    ? [batteryReading(phoneName, true, relay.percent, relay.pluggedIn, 100, 40, relay.charging)] : []
  readonly property var fitbitBatteries: relay.fitbitAvailable
    ? [Object.assign(batteryReading("Fitbit", true, relay.fitbitPercent, null), {updatedAt: relay.fitbitUpdatedAt})] : []
  readonly property var accessoryBatteries: keyboardBatteries.concat(mouseBatteries, earbudBatteries, phoneBatteries, fitbitBatteries)
  readonly property var batteries: (batteryAvailable ? [laptopBattery] : []).concat(accessoryBatteries)

  // Every source uses the same visibility and unknown-value rules. A missing
  // percentage is not zero; a missing power report is not "unplugged".
  function percent(value, maximum = 100) {
    return typeof value === "number" && isFinite(value) && value >= 0 && value <= maximum
      ? Math.round(value * 100 / maximum) : null;
  }

  function batteryReading(name, connected, level, pluggedIn, maximum = 100, lowThreshold = 20, charging = null) {
    const available = connected === true || pluggedIn === true;
    return {
      name: name,
      available: available,
      percent: available ? percent(level, maximum) : null,
      lowThreshold: lowThreshold,
      pluggedIn: available && typeof pluggedIn === "boolean" ? pluggedIn : null,
      charging: available && typeof charging === "boolean" ? charging : null
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

  function mouseExternalPower(power, device) {
    const hidpp = power?.ready && power.isPresent && power.type === UPowerDeviceType.Mouse
      && /^hidpp_battery_/.test(power.nativePath || "");
    // Some HID++ batteries report online=0 while Charging; UPower removes
    // their object although sysfs still reports charge correctly. Resolve the
    // live kernel reading by exact Bluetooth address, independently of UPower.
    if (telemetry?.systemFresh) {
      const address = String(device.address || "").toUpperCase();
      const readings = telemetry.hidppBatteries ?? [];
      const matches = readings.filter(reading => reading.address && reading.address === address);
      if (matches.length > 1) return null;
      const raw = matches.length === 1 ? matches[0] : hidpp
        ? readings.find(reading => reading.nativePath === power.nativePath
          && (!reading.address || reading.address === address)) : null;
      if (raw) {
        if (raw.status === "Charging" || raw.status === "Full") return true;
        if (raw.status === "Discharging") return false;
        return null;
      }
    }
    if (!device.connected && !hidpp) return null;
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

}
