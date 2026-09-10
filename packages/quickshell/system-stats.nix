{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "quickshell-system-stats";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../../tools/quickshell/system-stats;
    fileset = lib.fileset.unions [
      ../../tools/quickshell/system-stats/Cargo.toml
      ../../tools/quickshell/system-stats/Cargo.lock
      ../../tools/quickshell/system-stats/src
      ../../tools/quickshell/system-stats/tests
    ];
  };
  cargoLock.lockFile = ../../tools/quickshell/system-stats/Cargo.lock;
  meta = {
    description = "Local system telemetry for Quickshell";
    mainProgram = "quickshell-system-stats";
    platforms = lib.platforms.linux;
  };
}
