{
  config,
  lib,
  pkgs,
  ...
}: let
  helpers = import ./helpers.nix {inherit lib;};
  pwaAppIds = import ./pwa-apps.nix;
  voxtypePackage = config.programs.voxtype.package;
in {
  imports = [./uwsm-env.nix];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    systemd.enable = false;

    extraConfig = ''
      function quickshell_dismiss_notification()
        if (quickshell_notification_deadline or 0) <= os.time() then
          return false
        end
        quickshell_notification_deadline = 0
        hl.exec_cmd(${helpers.toLua "${pkgs.quickshell}/bin/qs --config top-bar ipc call topbar dismissNotification"})
        return true
      end
    '';

    submaps = import ./submaps.nix {
      inherit helpers voxtypePackage;
    };

    settings = lib.mergeAttrsList [
      (import ./settings.nix {inherit helpers;})
      (import ./workspaces.nix {inherit pwaAppIds;})
      (import ./bindings.nix {
        inherit
          helpers
          lib
          pkgs
          voxtypePackage
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
