{
  config,
  lib,
  localPackages,
  pkgs,
  ...
}: let
  helpers = import ./helpers.nix {inherit lib;};
  pwaAppIds = import ./pwa-apps.nix;
  voxtypePackage = config.programs.voxtype.package;
  # Set false to restore opaque Quickshell backgrounds permanently.
  enableLiquidGlass = true;
in {
  imports = [./uwsm-env.nix];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    systemd.enable = false;
    plugins = lib.optional enableLiquidGlass localPackages.liquidGlass;

    extraConfig = ''
      local keyboard_cheatsheet_shown = false

      function quickshell_show_keyboard_cheatsheet()
        keyboard_cheatsheet_shown = true
        hl.dispatch(hl.dsp.event("keyboard-cheatsheet:show"))
      end

      function quickshell_hide_keyboard_cheatsheet()
        keyboard_cheatsheet_shown = false
        hl.dispatch(hl.dsp.event("keyboard-cheatsheet:hide"))
      end

      function quickshell_cycle_keyboard_cheatsheet(backward)
        if not keyboard_cheatsheet_shown then
          return false
        end
        hl.dispatch(hl.dsp.event(backward
          and "keyboard-cheatsheet:previous" or "keyboard-cheatsheet:next"))
        return true
      end

      hl.on("keybinds.submap", quickshell_hide_keyboard_cheatsheet)
      hl.on("config.reloaded", quickshell_hide_keyboard_cheatsheet)

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
      (import ./settings.nix {
        inherit helpers;
        lafayetteKeymap = import ./lafayette.nix {inherit pkgs;};
      })
      (import ./workspaces.nix {inherit pwaAppIds;})
      (import ./bindings.nix {
        hyprlockPackage = config.programs.hyprlock.package;
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
