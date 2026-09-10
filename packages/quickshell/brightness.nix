{
  lib,
  rustPlatform,
  makeBinaryWrapper,
  bash,
  coreutils,
  brightnessctl,
  ddcutil,
  hyprland,
}:
rustPlatform.buildRustPackage {
  pname = "quickshell-brightness";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../../tools/quickshell/brightness;
    fileset = lib.fileset.unions [
      ../../tools/quickshell/brightness/Cargo.toml
      ../../tools/quickshell/brightness/Cargo.lock
      ../../tools/quickshell/brightness/src
      ../../tools/quickshell/brightness/tests
    ];
  };
  cargoLock.lockFile = ../../tools/quickshell/brightness/Cargo.lock;
  nativeBuildInputs = [makeBinaryWrapper];
  nativeCheckInputs = [bash coreutils];
  QS_TEST_SHELL = "${bash}/bin/sh";
  postInstall = ''
    wrapProgram "$out/bin/quickshell-brightness" \
      --prefix PATH : ${lib.makeBinPath [brightnessctl ddcutil hyprland]}
  '';
  meta = {
    description = "Monitor brightness control for Quickshell";
    mainProgram = "quickshell-brightness";
    platforms = lib.platforms.linux;
  };
}
