{
  lib,
  rustPlatform,
  pkg-config,
  dbus,
}:
rustPlatform.buildRustPackage {
  pname = "battery-relay-receiver";
  version = "0.6.0";
  src = lib.fileset.toSource {
    root = ../tools/battery-relay/receiver;
    fileset = lib.fileset.unions [
      ../tools/battery-relay/receiver/Cargo.toml
      ../tools/battery-relay/receiver/Cargo.lock
      ../tools/battery-relay/receiver/src
    ];
  };
  cargoLock.lockFile = ../tools/battery-relay/receiver/Cargo.lock;
  nativeBuildInputs = [pkg-config];
  buildInputs = [dbus];
  meta = {
    description = "Phone/Fitbit BLE relay and independent, connection-free Pixel Buds Fast Pair battery reader";
    mainProgram = "battery-relay-receiver";
    platforms = lib.platforms.linux;
  };
}
