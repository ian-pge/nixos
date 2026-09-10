{
  writeShellApplication,
  coreutils,
  jq,
  nh,
  util-linux,
  systemd,
}:
writeShellApplication {
  name = "quickshell-nix-cleaner";
  runtimeInputs = [coreutils jq nh util-linux];
  text = ''
    export QS_CLEAN_ELEVATOR=${systemd}/bin/run0
    ${builtins.readFile ../../tools/quickshell/nix-cleaner/clean-installer.sh}
  '';
}
