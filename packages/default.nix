{
  inputs,
  pkgs,
}: let
  liquidGlassClient = pkgs.callPackage ./quickshell/liquid-glass-client.nix {};
  quickshellRuntime = pkgs.callPackage ./quickshell/runtime.nix {inherit liquidGlassClient;};
  quickshellBeeper = pkgs.callPackage ./quickshell/beeper.nix {};
  quickshellSystemStats = pkgs.callPackage ./quickshell/system-stats.nix {};
  quickshellWeather = pkgs.callPackage ./quickshell/weather.nix {};
  batteryRelayReceiver = pkgs.callPackage ./battery-relay.nix {};
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  quickshellDesktop = pkgs.callPackage ./quickshell/desktop.nix {
    inherit quickshellBeeper quickshellSystemStats quickshellWeather batteryRelayReceiver;
    inherit (llmAgents) claude-code codex;
  };
in
  {
    inherit liquidGlassClient quickshellRuntime quickshellDesktop quickshellBeeper quickshellSystemStats quickshellWeather batteryRelayReceiver;
    liquidGlass = pkgs.callPackage ./quickshell/liquid-glass.nix {};
    hyprlock = pkgs.writeShellApplication {
      name = "hyprlock";
      runtimeInputs = [pkgs.hyprland pkgs.jq pkgs.coreutils];
      text = ''
        # Select at launch: prefer the desk display, then any external output,
        # then the laptop. An IPC failure must never prevent locking.
        HYPRLOCK_MONITOR="$(timeout 2 hyprctl monitors -j | jq -r '
          [.[] | select(.disabled != true) | select((.mirrorOf // "none") == "none")]
          | sort_by([
              (if .name == "DP-2" then 0
               elif (.name | test("^(eDP|LVDS|DSI)-")) then 2
               else 1 end), .name
            ])
          | .[0].name // ""
        ')" || HYPRLOCK_MONITOR=""
        export HYPRLOCK_MONITOR
        exec ${pkgs.hyprlock}/bin/hyprlock "$@"
      '';
    };
    hyprlockAge = pkgs.callPackage ./hyprlock-age.nix {};
    quickshellBrightness = pkgs.callPackage ./quickshell/brightness.nix {};
    quickshellBeeperPreview = pkgs.callPackage ./quickshell/beeper-preview.nix {
      inherit quickshellRuntime quickshellDesktop;
    };
    quickshellNixCleaner = pkgs.callPackage ./quickshell/nix-cleaner.nix {};
    quickshellSpeedtest = pkgs.callPackage ./quickshell/speedtest.nix {};
    quickshellGpuMonitor = pkgs.callPackage ./quickshell/gpu-monitor.nix {};
  }
  // import ./quickshell/update.nix {inherit pkgs;}
