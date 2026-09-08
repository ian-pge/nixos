{
  lib,
  rustPlatform,
  bash,
  coreutils,
  util-linux,
  runCommand,
}:
rustPlatform.buildRustPackage {
  pname = "quickshell-helpers";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ../tools/quickshell/rust;
    fileset = lib.fileset.unions [
      ../tools/quickshell/rust/Cargo.toml
      ../tools/quickshell/rust/Cargo.lock
      ../tools/quickshell/rust/src
      ../tools/quickshell/rust/tests
    ];
  };
  cargoLock.lockFile = ../tools/quickshell/rust/Cargo.lock;
  nativeCheckInputs = [bash coreutils util-linux];
  QS_TEST_SHELL = "${bash}/bin/sh";
  QS_TEST_SYSTEM = runCommand "quickshell-test-system" {} ''
    mkdir -p "$out/bin"
    ln -s ${runCommand "quickshell-test-system-path" {} "mkdir -p $out/bin"} "$out/sw"
    printf '#!${bash}/bin/sh\nexit 99\n' > "$out/bin/switch-to-configuration"
    chmod +x "$out/bin/switch-to-configuration"
  '';
  meta = {
    description = "Native update and monitor helpers for Quickshell";
    platforms = lib.platforms.linux;
  };
}
