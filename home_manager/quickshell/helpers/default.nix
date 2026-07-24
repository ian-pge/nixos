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

  speedtestRunner = pkgs.writeShellApplication {
    name = "quickshell-speedtest";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      ookla-speedtest
    ];
    text = ''
      generation="''${1:-0}"
      temp_dir="$(mktemp -d)"
      output_pipe="$temp_dir/output"
      stderr_file="$temp_dir/stderr"
      speedtest_pid=""
      parser_pid=""
      mkfifo "$output_pipe"

      cleanup() {
        rm -rf "$temp_dir"
      }

      terminate() {
        for pid in "$speedtest_pid" "$parser_pid"; do
          if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
          fi
        done
        for pid in "$speedtest_pid" "$parser_pid"; do
          if [[ -n "$pid" ]]; then
            wait "$pid" 2>/dev/null || true
          fi
        done
        cleanup
        exit 143
      }

      trap terminate TERM INT
      trap cleanup EXIT

      jq --unbuffered -c --arg generation "$generation" \
        '. + {generation: $generation}' <"$output_pipe" &
      parser_pid="$!"

      speedtest --accept-license --accept-gdpr --format=json --progress=yes \
        --progress-update-interval=500 >"$output_pipe" 2>"$stderr_file" &
      speedtest_pid="$!"

      speedtest_status=0
      wait "$speedtest_pid" || speedtest_status="$?"
      parser_status=0
      wait "$parser_pid" || parser_status="$?"

      if [[ "$speedtest_status" -ne 0 || "$parser_status" -ne 0 ]]; then
        error="$(cat "$stderr_file")"
        jq -cn --arg generation "$generation" \
          --arg error "''${error:-Speed test failed}" \
          '{type: "error", generation: $generation, error: $error}'
      fi
    '';
  };
in {
  home.packages = [
    updateChecker
    updateInstaller
    systemStats
    gpuMonitor
    weather
    speedtestRunner
  ];
}
