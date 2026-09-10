{
  lib,
  rustPlatform,
  makeBinaryWrapper,
  bash,
  coreutils,
  tabctl,
}:
rustPlatform.buildRustPackage {
  pname = "quickshell-chrome-tabs";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../../tools/quickshell/chrome-tabs;
    fileset = lib.fileset.unions [
      ../../tools/quickshell/chrome-tabs/Cargo.toml
      ../../tools/quickshell/chrome-tabs/Cargo.lock
      ../../tools/quickshell/chrome-tabs/src
      ../../tools/quickshell/chrome-tabs/tests
    ];
  };
  cargoLock.lockFile = ../../tools/quickshell/chrome-tabs/Cargo.lock;
  nativeBuildInputs = [makeBinaryWrapper];
  nativeCheckInputs = [bash coreutils];
  QS_TEST_SHELL = "${bash}/bin/sh";
  postInstall = ''
    wrapProgram "$out/bin/quickshell-chrome-tabs" \
      --prefix PATH : ${lib.makeBinPath [tabctl]}
  '';
  meta = {
    description = "TabCtl integration and local Chrome favicon cache for Quickshell";
    mainProgram = "quickshell-chrome-tabs";
    platforms = lib.platforms.linux;
  };
}
