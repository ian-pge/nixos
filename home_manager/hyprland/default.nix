{
  lib,
  pkgs,
  ...
}: let
  helpers = import ./helpers.nix {inherit lib;};
  pwaAppIds = import ./pwa-apps.nix;
in {
  imports = [./uwsm-env.nix];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    systemd.enable = false;

    settings = lib.mergeAttrsList [
      (import ./settings.nix {inherit helpers;})
      (import ./workspaces.nix {inherit pwaAppIds;})
      (import ./bindings.nix {
        inherit
          helpers
          lib
          pkgs
          ;
      })
      (import ./rules.nix {inherit pwaAppIds;})
      (import ./startup.nix {
        inherit
          helpers
          lib
          pkgs
          ;
      })
    ];
  };
}
