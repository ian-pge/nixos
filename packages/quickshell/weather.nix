{
  lib,
  rustPlatform,
  makeBinaryWrapper,
  curl,
}:
rustPlatform.buildRustPackage {
  pname = "quickshell-weather";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../../tools/quickshell/weather;
    fileset = lib.fileset.unions [
      ../../tools/quickshell/weather/Cargo.toml
      ../../tools/quickshell/weather/Cargo.lock
      ../../tools/quickshell/weather/src
    ];
  };
  cargoLock.lockFile = ../../tools/quickshell/weather/Cargo.lock;
  nativeBuildInputs = [makeBinaryWrapper];
  postInstall = ''
    wrapProgram "$out/bin/quickshell-weather" \
      --prefix PATH : ${lib.makeBinPath [curl]}
  '';
  meta = {
    description = "Shared weather and calendar forecasts for Quickshell";
    mainProgram = "quickshell-weather";
    platforms = lib.platforms.linux;
  };
}
