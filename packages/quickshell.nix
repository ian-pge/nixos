{
  pkgs,
  gpuUsage,
}: let
  rustHelpers = pkgs.callPackage ./quickshell-rust.nix {};
  # Compiled wrappers give each command only its runtime tools. The compiler,
  # Cargo and crate sources are build dependencies, not session packages.
  rustCommand = name: runtimeInputs: extraArgs:
    pkgs.runCommand name {nativeBuildInputs = [pkgs.makeBinaryWrapper];} ''
      mkdir -p "$out/bin"
      makeWrapper ${rustHelpers}/bin/${name} "$out/bin/${name}" \
        --prefix PATH : ${pkgs.lib.makeBinPath runtimeInputs} ${extraArgs}
    '';

  updateChecker = rustCommand "quickshell-update-checker" [pkgs.nix] "";

  updateDiff = rustCommand "quickshell-update-diff" [pkgs.nix] "";

  updateActivator = pkgs.writeShellApplication {
    name = "quickshell-update-activator";
    runtimeInputs = with pkgs; [
      coreutils
      nix
    ];
    text = builtins.readFile ../tools/quickshell/activate-system.sh;
  };

  updateInstaller = rustCommand "quickshell-update-installer" (with pkgs; [nh nix quickshell]) ''
    --set QS_UPDATE_ACTIVATOR ${updateActivator}/bin/quickshell-update-activator \
    --set QS_UPDATE_ELEVATOR ${pkgs.systemd}/bin/run0
  '';

  nixCleaner = pkgs.writeShellApplication {
    name = "quickshell-nix-cleaner";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      nh
      util-linux
    ];
    text = ''
      export QS_CLEAN_ELEVATOR=${pkgs.systemd}/bin/run0
      ${builtins.readFile ../tools/quickshell/clean-installer.sh}
    '';
  };

  brightness = rustCommand "quickshell-brightness" (with pkgs; [brightnessctl ddcutil hyprland]) "";

  systemStats = pkgs.writeShellApplication {
    name = "quickshell-system-stats";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec python3 ${../tools/quickshell/system-stats.py}
    '';
  };

  gpuMonitor = pkgs.writeShellApplication {
    name = "quickshell-gpu-monitor";
    text = ''
      export LD_LIBRARY_PATH=/run/opengl-driver/lib
      exec ${gpuUsage}/bin/gpu-usage-waybar "$@"
    '';
  };

  weather = pkgs.writeShellApplication {
    name = "quickshell-weather";
    runtimeInputs = [pkgs.wttrbar];
    text = ''
      exec wttrbar --nerd "$@"
    '';
  };

  speedtestRunner = pkgs.writeShellApplication {
    name = "quickshell-speedtest";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      ookla-speedtest
    ];
    text = builtins.readFile ../tools/quickshell/speedtest.sh;
  };
in {
  quickshellRust = rustHelpers;
  quickshellUpdateChecker = updateChecker;
  quickshellUpdateDiff = updateDiff;
  quickshellUpdateActivator = updateActivator;
  quickshellUpdateInstaller = updateInstaller;
  quickshellNixCleaner = nixCleaner;
  quickshellBrightness = brightness;
  quickshellSystemStats = systemStats;
  quickshellGpuMonitor = gpuMonitor;
  quickshellWeather = weather;
  quickshellSpeedtest = speedtestRunner;
}
