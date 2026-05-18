{
  pkgs,
  config,
  ...
}: {
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    ## Main bar configuration ─ straight conversion of your JSON
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 0;
        margin-top = 10;
        margin-left = 5;
        margin-right = 5;
        margin-bottom = 0;
        # output = "eDP-1";

        modules-left = [
          "custom/launcher"
          "custom/nixos"
          "network"
          "bluetooth"
          "disk"
          "cpu"
          "memory"
          "custom/gpu"
        ];

        modules-center = ["hyprland/workspaces"];

        modules-right = [
          "upower"
          "wireplumber"
          "backlight"
          "custom/weather"
          "clock#second"
          "clock"
        ];

        ## ───── Hyprland workspaces ─────
        "hyprland/workspaces" = {
          active-only = false;
          all-outputs = true;
          show-special = false;
          on-click = "activate";
          format = "{icon}";
          persistent-workspaces = {
            "*" = 8;
          };
          format-icons = {
            active = "󰮯"; # Pacman: current workspace
            default = "󰊠"; # Ghost: workspace has apps
            empty = ""; # Dot: empty workspace
          };
        };

        ## ───── Clocks ─────
        clock = {
          format = " {:%H:%M}";
          timezone = "Europe/Paris";
          tooltip = false;
        };
        "clock#second" = {
          format = " {:%b %d %Y}";
          tooltip = false;
        };

        "custom/weather" = {
          format = "{}°";
          tooltip = true;
          interval = 3600;
          exec = "wttrbar --nerd";
          return-type = "json";
        };

        ## ───── System modules ─────
        cpu = {
          interval = 1;
          format = " {usage}%";
          on-click = "ghostty -e htop";
        };

        memory = {
          interval = 1;
          format = "  {}%";
          on-click = "ghostty -e htop";
        };

        "custom/gpu" = {
          exec = "LD_LIBRARY_PATH=/run/opengl-driver/lib gpu-usage-waybar";
          format = "{icon} {text}";
          format-icons = "";
          return-type = "json";
          on-click = "ghostty -e nvtop";
        };

        backlight = {
          format = "{icon} {percent}%";
          format-icons = [
            "󰃞"
            "󰃟"
            "󰃠"
          ];
          tooltip = false;
        };

        wireplumber = {
          format = "{icon} {volume}%";
          format-muted = "󰖁";
          format-icons = ["󰕿" "󰖀" "󰕾"];
          on-click = "pgrep -x pulsemixer >/dev/null 2>&1 || ghostty --class=dev.me.audio --title=Audio -e pulsemixer";
        };

        network = {
          format-wifi = "{icon}";
          format-icons = ["󰤟" "󰤢" "󰤥" "󰤨"];
          interval = 5;
          format-ethernet = "󰈀";
          format-disconnected = "󰤭 ";
          format-disabled = "󰤭";
          format-disabled-if-down = true;
          tooltip-format-wifi = "{essid}";
          tooltip-format-ethernet = "{ifname}";
          tooltip-format-disconnected = "Disconnected";
          tooltip-format-disabled = "Wi-Fi Off";
          on-click = "hyprctl clients | grep -q 'class: dev.me.wifi' || ghostty --class=dev.me.wifi --title=WiFi -e wlctl";
        };

        "custom/launcher" = {
          format = "";
          on-click = "pgrep -x fuzzel >/dev/null 2>&1 || fuzzel";
          tooltip = false;
        };

        # ───── UPDATED CUSTOM/NIXOS MODULE ─────
        "custom/nixos" = {
          exec = "nixos-update-checker";
          return-type = "json";
          interval = 1800; # Check every 30 minutes
          signal = 8; # Allows manual refresh

          # Left-click: Run update in terminal
          on-click = "ghostty -e nixos-update-installer";

          # Right-click: Force check NOW (and refresh icon)
          on-click-right = "nixos-update-checker force && pkill -SIGRTMIN+8 waybar";

          format = "{icon}";
          tooltip = true;

          format-icons = {
            updated = ""; # Icon when clean
            has-updates = ""; # Icon when updates exist
          };
        };

        bluetooth = {
          format = "󰂲";
          format-connected = "󰂯";
          tooltip-format = "{controller_alias}";
          tooltip-format-connected = "{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}";
          format-off = "󰂲";
          on-click = "pgrep -x bluetui >/dev/null 2>&1 || ghostty --class=dev.me.bluetooth --title=Bluetooth -e bluetui";
        };

        upower = {
          format = " {percentage}";
          tooltip = false;
        };

        disk = {
          interval = 30;
          format = " {percentage_used}%";
          path = "/";
          on-click = "ghostty -e ncdu";
        };
      };
    };

    ## CSS theme – pasted directly
    style = ''
      @define-color rosewater #f4dbd6;
      @define-color flamingo  #f0c6c6;
      @define-color pink      #f5bde6;
      @define-color mauve     #c6a0f6;
      @define-color red       #ed8796;
      @define-color maroon    #ee99a0;
      @define-color peach     #f5a97f;
      @define-color yellow    #eed49f;
      @define-color green     #a6da95;
      @define-color teal      #8bd5ca;
      @define-color sky       #91d7e3;
      @define-color sapphire  #7dc4e4;
      @define-color blue      #8aadf4;
      @define-color lavender  #b7bdf8;
      @define-color text      #cad3f5;
      @define-color base      #24273a;
      @define-color crust     #181926;
      @define-color mantle    #1e2030;
      @define-color subtext0  #a5adcb;
      @define-color overlay2  #939ab7;
      @define-color overlay1  #8087a2;
      @define-color overlay0  #6e738d;
      @define-color surface2  #5b6078;
      @define-color surface1  #494d64;
      @define-color surface0  #363a4f;

      * {
          font-family: "Ubuntu Nerd Font";
          font-weight: bold;
          font-size: 15px;
      }

      window#waybar {
          background: none;
      }

      tooltip,
      tooltip.background,
      tooltip decoration,
      tooltip window,
      tooltip box {
          background: none;
          background-color: transparent;
          border: none;
          border-radius: 0;
          margin: 0;
          padding: 0;
          box-shadow: none;
          text-shadow: none;
      }

      tooltip label {
          background: none;
          background-color: @surface0;
          border: none;
          border-radius: 14px;
          color: @text;
          font-size: 14px;
          font-weight: 700;
          margin: 0;
          padding: 10px 12px;
          box-shadow: none;
          text-shadow: none;
      }

      #clock, #cpu, #memory, #backlight, #custom-gpu,
      #wireplumber, #network, #bluetooth, #custom-nixos,
      #upower, #disk, #workspaces, #custom-launcher, #custom-weather {
          background-color: @crust;
          border-radius: 100px;
          padding: 0px 10px;
          margin: 0px 5px;
          font-size: 16px;
      }

      #cpu            { color: @sky;       }
      #memory         { color: @mauve;     }
      #custom-gpu     { color: @green;     }
      #backlight      { color: @yellow;    }
      #network        { color: @maroon;    }
      #wireplumber     { color: @lavender;  }
      #clock          { color: @red;       }
      #clock.second   { color: @teal;      }
      #custom-launcher{ color: @sapphire;  }
      #bluetooth      { color: @blue;      }
      #upower         { color: @rosewater; }
      #disk           { color: @peach;     }
      #custom-nixos  { color: @flamingo;  }
      #custom-weather { color: @pink;      }

      #clock, #cpu, #memory, #backlight, #custom-gpu,
      #wireplumber, #network, #bluetooth, #custom-nixos,
      #upower, #disk, #custom-launcher, #custom-weather {
          transition-property: background-color, color, box-shadow;
          transition-duration: 0.22s;
          transition-timing-function: ease;
      }

      #cpu:hover             { background-color: @sky;       color: @crust; }
      #memory:hover          { background-color: @mauve;     color: @crust; }
      #custom-gpu:hover      { background-color: @green;     color: @crust; }
      #backlight:hover       { background-color: @yellow;    color: @crust; }
      #network:hover         { background-color: @maroon;    color: @crust; }
      #wireplumber:hover     { background-color: @lavender;  color: @crust; }
      #clock:hover           { background-color: @red;       color: @crust; }
      #clock.second:hover    { background-color: @teal;      color: @crust; }
      #custom-launcher:hover { background-color: @sapphire;  color: @crust; }
      #bluetooth:hover       { background-color: @blue;      color: @crust; }
      #upower:hover          { background-color: @rosewater; color: @crust; }
      #disk:hover            { background-color: @peach;     color: @crust; }
      #custom-nixos:hover    { background-color: @flamingo;  color: @crust; }
      #custom-weather:hover  { background-color: @pink;      color: @crust; }

      #workspaces {
          padding: 6px 6px;
          border-radius: 20px;
      }

      #workspaces button {
          min-width: 40px;
          min-height: 24px;
          padding: 0px 0px;
          margin: 0px 0px;
          background: transparent;
          border: none;
          border-radius: 16px;
          color: #ffcc33;
          transition-property: min-width, background-color, color;
          transition-duration: 0.4s;
          transition-timing-function: cubic-bezier(0.25, 0.46, 0.45, 0.94);
      }

      #workspaces button.active {
          min-width: 60px;
          background-color: #ff33cc;
          color: @crust;
      }

      #workspaces button:hover {
          background-color: @surface0;
          color: #ff33cc;
      }

      #workspaces button.active:hover {
          background-color: #ff33cc;
          color: @crust;
      }

      #workspaces button.empty {
          color: @overlay0;
      }


    '';
  };

  home.packages = with pkgs; [
    wttrbar

    jq # Ensure jq is installed for JSON formatting

    # ───── 1. THE CHECKER SCRIPT (Smart Wrapper) ─────
    (writeShellScriptBin "nixos-update-checker" ''
      #!/usr/bin/env bash
      set -uo pipefail

      CACHE_FILE="/tmp/nixos-update-status.json"
      FLAKE_DIR="$HOME/.config/nixos"

      # 1. The Heavy Check Function
      do_check() {
        # Create temp directory to avoid locking the real flake
        TMP_DIR=$(mktemp -d)
        trap 'rm -rf "$TMP_DIR"' EXIT

        cp "$FLAKE_DIR/flake.nix" "$TMP_DIR/"
        cp "$FLAKE_DIR/flake.lock" "$TMP_DIR/" 2>/dev/null || true

        # Run the update in dry-run mode
        update_output=$(nix flake update --flake "$TMP_DIR" 2>&1 || echo "Error checking")

        # Parse the output using your original AWK logic
        updates=$(echo "$update_output" | awk '
          /Updated input/ {
              # Match name inside single quotes
              match($0, /\x27[^\x27]+\x27/);
              if (RSTART > 0) {
                name = substr($0, RSTART+1, RLENGTH-2);
              }
          }
          /→/ {
              # Match date inside parentheses (YYYY-MM-DD)
              match($0, /\([0-9]{4}-[0-9]{2}-[0-9]{2}\)/);
              if (RSTART > 0) {
                date = substr($0, RSTART+1, RLENGTH-2);
              } else {
                date = "unknown";
              }
              # Print "nixpkgs: 2026-02-09"
              print name ": " date;
          }
        ')

        # Count how many updates found
        count=$(echo -n "$updates" | grep -c '^' || true)

        if [[ -n "$updates" && "$count" -gt 0 ]]; then
          # Safely escape the list for JSON (requires jq)
          tooltip_esc=$(echo "$updates" | jq -R -s '.')

          # Write JSON: icon is "has-updates", tooltip has the list
          printf '{"text":"","alt":"has-updates","class":"has-updates","tooltip":%s}\n' "$tooltip_esc" > "$CACHE_FILE"
        else
          # Write JSON: icon is "updated", tooltip is simple text
          printf '{"text":"","alt":"updated","class":"updated","tooltip":"System is up to date"}\n' > "$CACHE_FILE"
        fi
      }

      # 2. Logic Controller

      # A) Force check (Right Click)
      if [[ "''${1:-}" == "force" ]]; then
        do_check
        cat "$CACHE_FILE"
        exit 0
      fi

      # B) Interval Check (Every 30m)
      current_time=$(date +%s)
      if [[ -f "$CACHE_FILE" ]]; then
        file_time=$(stat -c %Y "$CACHE_FILE")
        age=$((current_time - file_time))
      else
        age=99999
      fi

      # Only run check if cache is older than 30 mins (1800s)
      if [[ $age -ge 1800 ]]; then
        do_check
      fi

      # C) Always print the result for Waybar
      if [[ -f "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
      else
        # Fallback if first run hasn't finished
        echo '{"text":"","alt":"updated","class":"updated","tooltip":"Checking..."}'
      fi
    '')

    # ───── 2. THE BUILDER SCRIPT (Click Logic) ─────
    (writeShellScriptBin "nixos-update-installer" ''
      #!/usr/bin/env bash
      set -e
      echo "📦 Starting update..."
      cd ~/.config/nixos

      # Update lockfile
      nix flake update

      # Rebuild System (using nh or nixos-rebuild)
      if nh os switch; then
        echo ""
        echo "✅ Update Complete!"

        # 1. Overwrite the cache with "Up to date" status
        echo '{"text":"", "alt":"updated", "class":"updated", "tooltip":"Just updated"}' > /tmp/nixos-update-status.json

        # 2. Signal Waybar to refresh the module immediately
        pkill -SIGRTMIN+8 waybar

        echo "Icon refreshed."
        read -p "Press Enter to close..."
      else
        echo "❌ Update Failed."
        read -p "Press Enter to inspect error..."
      fi
    '')
    (rustPlatform.buildRustPackage {
      pname = "gpu-usage-waybar";
      version = "v0.1.24"; # latest release, 3 May 2025 :contentReference[oaicite:0]{index=0}

      src = fetchFromGitHub {
        # pulls the exact crate published to crates.io
        owner = "PolpOnline";
        repo = "gpu-usage-waybar";
        rev = "v0.1.23";
        hash = "sha256-DUIKiUgTy4jn8NZZvjC0zuA993Sbq1Fvr7tvJw3+tNw="; # first run with lib.fakeSha256, copy real hash
      };

      # Cargo.lock lives in the repo, so just grab the hashes once:
      cargoHash = "sha256-X3Ak0K1kt7++tE7qZgy8GaRzqemUNTJ3z1yGBJZyA4s=";
      doCheck = false; # upstream has no tests yet :contentReference[oaicite:1]{index=1}
    })
  ];
  nix.extraOptions = ''
    !include /home/ian/.config/nix/access-tokens
  '';
}
