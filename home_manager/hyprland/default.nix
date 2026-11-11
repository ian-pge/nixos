{
  config,
  lib,
  localPackages,
  pkgs,
  ...
}: let
  helpers = import ./helpers.nix {inherit lib;};
  pwaAppIds = import ./pwa-apps.nix;
  voxtypePackage = config.services.voxtype.package;
in {
  imports = [./uwsm-env.nix];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    systemd.enable = false;
    plugins =
      lib.optional
      (config.programs.quickshell.backgroundStyle == "liquid-glass")
      localPackages.liquidGlass;

    extraConfig =
      builtins.readFile ./workspace-policy.lua
      + ''
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

        -- Opening an empty scratchpad launches its PWA. The window rules in
        -- rules.nix route the new window back to the same special workspace.
        local special_workspace_apps = ${helpers.toLua {
          "special:Agenda" = "google-chrome-stable --profile-directory=Default --app-id=${pwaAppIds.calendar}";
          "special:Music" = "google-chrome-stable --profile-directory=Default --app-id=${pwaAppIds.spotify}";
          "special:Notes" = "google-chrome-stable --profile-directory=Default --app-id=${pwaAppIds.keep}";
        }}

        hl.on("workspace.created", function(workspace)
          local command = special_workspace_apps[workspace.addressable_name]
          if command and workspace.is_empty then
            hl.exec_cmd(command)
          end
        end)
      '';

    submaps = import ./submaps.nix {
      inherit helpers voxtypePackage;
    };

    settings = lib.mergeAttrsList [
      (import ./settings.nix {
        inherit helpers;
        lafayetteKeymap = import ./lafayette.nix {inherit pkgs;};
      })
      (import ./workspaces.nix)
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
