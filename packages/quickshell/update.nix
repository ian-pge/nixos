{pkgs}: let
  # One build for the three commands that share the update protocol and state.
  binaries = pkgs.rustPlatform.buildRustPackage {
    pname = "quickshell-update";
    version = "0.1.0";
    src = pkgs.lib.fileset.toSource {
      root = ../../tools/quickshell/update;
      fileset = pkgs.lib.fileset.unions [
        ../../tools/quickshell/update/Cargo.toml
        ../../tools/quickshell/update/Cargo.lock
        ../../tools/quickshell/update/src
        ../../tools/quickshell/update/tests
      ];
    };
    cargoLock.lockFile = ../../tools/quickshell/update/Cargo.lock;
    nativeCheckInputs = with pkgs; [bash coreutils util-linux];
    QS_TEST_SHELL = "${pkgs.bash}/bin/sh";
    QS_TEST_SYSTEM = pkgs.runCommand "quickshell-test-system" {} ''
      mkdir -p "$out/bin"
      ln -s ${pkgs.runCommand "quickshell-test-system-path" {} "mkdir -p $out/bin"} "$out/sw"
      printf '#!${pkgs.bash}/bin/sh\nexit 99\n' > "$out/bin/switch-to-configuration"
      chmod +x "$out/bin/switch-to-configuration"
    '';
    meta = {
      description = "Update checker, installer and closure diff for Quickshell";
      platforms = pkgs.lib.platforms.linux;
    };
  };

  wrap = name: runtimeInputs: extraArgs:
    pkgs.runCommand name {nativeBuildInputs = [pkgs.makeBinaryWrapper];} ''
      mkdir -p "$out/bin"
      makeWrapper ${binaries}/bin/${name} "$out/bin/${name}" \
        --prefix PATH : ${pkgs.lib.makeBinPath runtimeInputs} ${extraArgs}
    '';

  activator = pkgs.writeShellApplication {
    name = "quickshell-update-activator";
    runtimeInputs = with pkgs; [coreutils nix];
    text = builtins.readFile ../../tools/quickshell/update/activate-system.sh;
  };
in {
  quickshellUpdateChecker = wrap "quickshell-update-checker" [pkgs.nix] "";
  quickshellUpdateDiff = wrap "quickshell-update-diff" [pkgs.nix] "";
  quickshellUpdateActivator = activator;
  quickshellUpdateInstaller = wrap "quickshell-update-installer" (with pkgs; [nh nix quickshell]) ''
    --set QS_UPDATE_ACTIVATOR ${activator}/bin/quickshell-update-activator \
    --set QS_UPDATE_ELEVATOR ${pkgs.systemd}/bin/run0
  '';
}
