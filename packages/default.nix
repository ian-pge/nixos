{
  inputs,
  pkgs,
}: let
  gpuUsage = pkgs.callPackage ./gpu-usage.nix {};
in
  {
    inherit gpuUsage;
    hyprlockAge = pkgs.callPackage ./hyprlock-age.nix {};
    tabctl = pkgs.callPackage ./tabctl.nix {src = inputs.tabctl;};
  }
  // import ./quickshell.nix {inherit pkgs gpuUsage;}
