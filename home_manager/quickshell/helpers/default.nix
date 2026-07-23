{pkgs, ...}: let
  gpuUsage = pkgs.rustPlatform.buildRustPackage {
    pname = "gpu-usage-waybar";
    version = "v0.1.24";

    src = pkgs.fetchFromGitHub {
      owner = "PolpOnline";
      repo = "gpu-usage-waybar";
      rev = "v0.1.23";
      hash = "sha256-DUIKiUgTy4jn8NZZvjC0zuA993Sbq1Fvr7tvJw3+tNw=";
    };

    cargoHash = "sha256-X3Ak0K1kt7++tE7qZgy8GaRzqemUNTJ3z1yGBJZyA4s=";
    doCheck = false;
  };

  updateChecker = pkgs.writeShellApplication {
    name = "quickshell-update-checker";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      jq
      nix
      util-linux
    ];
    text = builtins.readFile ./update-checker.sh;
  };

  updateInstaller = pkgs.writeShellApplication {
    name = "quickshell-update-installer";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      nh
      nix
      quickshell
    ];
    text = builtins.readFile ./update-installer.sh;
  };

  systemStats = pkgs.writeShellApplication {
    name = "quickshell-system-stats";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec python3 ${../top-bar/scripts/system-stats.py}
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
in {
  home.packages = [
    updateChecker
    updateInstaller
    systemStats
    gpuMonitor
    weather
  ];
}
