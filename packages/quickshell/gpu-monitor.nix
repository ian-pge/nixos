{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "quickshell-gpu-monitor";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../../tools/quickshell/gpu-monitor;
    fileset = lib.fileset.unions [
      ../../tools/quickshell/gpu-monitor/Cargo.toml
      ../../tools/quickshell/gpu-monitor/Cargo.lock
      ../../tools/quickshell/gpu-monitor/src
      ../../tools/quickshell/gpu-monitor/tests
    ];
  };
  cargoLock.lockFile = ../../tools/quickshell/gpu-monitor/Cargo.lock;
  meta = {
    description = "Native NVIDIA telemetry for Quickshell";
    mainProgram = "quickshell-gpu-monitor";
    platforms = lib.platforms.linux;
  };
}
