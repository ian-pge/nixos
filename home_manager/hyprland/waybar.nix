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
        margin-top = 10;
        margin-left = 5;
        margin-right = 5;
        margin-bottom = 0;
        # output = "eDP-1";

        modules-left = [
          "custom/launcher"
          "custom/nixos"
          "disk"
          "cpu"
          "memory"
          "custom/gpu"
        ];

        modules-center = ["hyprland/workspaces"];

        modules-right = [
          "network"
          "bluetooth"
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
          show-special = true;
          special-visible-only = true;
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
          exec = "wttrbar --location=Grenoble --nerd";
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
          format-wifi = "{icon} {essid}";
          format-icons = ["󰤟" "󰤢" "󰤥" "󰤨"];
          interval = 5;
          format-ethernet = "󰈀 {ifname}";
          format-disconnected = "󰤭 ";
          format-disabled = "󰤭 Off";
          format-disabled-if-down = true;
          tooltip-format = "{ifname} via {gwaddr}";
          on-click = "hyprctl clients | grep -q 'class: dev.me.wifi' || ghostty --class=dev.me.wifi --title=WiFi -e gazelle";
        };

        "custom/launcher" = {
          format = "";
          on-click = "pgrep -x fuzzel >/dev/null 2>&1 || fuzzel";
          tooltip = false;
        };

        # ───── UPDATED CUSTOM/NIXOS MODULE ─────
        "custom/nixos" = {
          exec = "waybar-update-checker";
          return-type = "json";
          interval = 3600; # Check every hour (network heavy!)
          signal = 8; # Allows manual update via signal

          # Left-click: Build & Switch (in terminal)
          on-click = "ghostty -e waybar-update-builder";

          # Right-click: Force check for updates NOW
          on-click-right = "pkill -SIGRTMIN+8 waybar";

          format = "{icon}{text}";
          tooltip = true;

          format-icons = {
            error = "";
            busy = "";
            has-updates = " "; # The icon when updates are found
            updated = ""; # The icon when system is clean
            outdated = "";
          };
        };

        bluetooth = {
          format = "󰂲";
          format-connected = "󰂯 {device_alias}";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          format-off = "󰂲 Off";
          on-click = "pgrep -x bluetui >/dev/null 2>&1 || ghostty --class=dev.me.bluetooth --title=Bluetooth -e bluetui";
        };

        upower = {
          format = " {percentage}";
          tooltip = true;
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

      #clock, #cpu, #memory, #backlight, #custom-gpu,
      #wireplumber, #network, #bluetooth, #custom-nixos,
      #upower, #disk, #workspaces, #custom-launcher, #custom-weather {
          background-color: @crust;
          border-radius: 10px;
          padding: 0px 10px;
          margin: 0px 5px;
          font-size: 16px;
      }

      #cpu            { color: @pink;      }
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
      #custom-weather { color: @flamingo;  }

      #workspaces button       { color: @text; background: none; border: none; }
      #workspaces button:hover { background: none; }
      #workspaces button.active{ color: #33ff33; }
    '';
  };

  home.packages = with pkgs; [
    wttrbar

    jq # Ensure jq is installed for JSON formatting

    # ───── 1. THE CHECKER SCRIPT (Tooltip Logic) ─────
    (writeShellScriptBin "waybar-update-checker" ''
      #!/usr/bin/env bash
      set -uo pipefail

      FLAKE_DIR="$HOME/.config/nixos"
      TMP_DIR=$(mktemp -d)
      trap 'rm -rf "$TMP_DIR"' EXIT

      if [[ -f "$FLAKE_DIR/flake.nix" ]]; then
        cp "$FLAKE_DIR/flake.nix" "$TMP_DIR/"
        cp "$FLAKE_DIR/flake.lock" "$TMP_DIR/" 2>/dev/null || true
      else
        echo '{"text":"?","alt":"error","tooltip":"No flake found"}'
        exit 0
      fi

      update_output=$(timeout 60s nix flake update --flake "$TMP_DIR" 2>&1 || echo "Error checking")

      if [[ "$update_output" == *"Error checking"* ]]; then
         echo '{"text":"","alt":"error","tooltip":"Timeout or network error"}'
         exit 0
      fi

      # ─── PARSING LOGIC ───
      updates=$(echo "$update_output" | awk '
        /Updated input/ {
            # 1. Match the name inside single quotes (Hex 27)
            match($0, /\x27[^\x27]+\x27/);
            if (RSTART > 0) {
              # Strip the quotes from the match
              name = substr($0, RSTART+1, RLENGTH-2);
            }
        }
        /→/ {
            # 2. Match the date inside parentheses: (YYYY-MM-DD)
            match($0, /\([0-9]{4}-[0-9]{2}-[0-9]{2}\)/);
            if (RSTART > 0) {
              date = substr($0, RSTART+1, RLENGTH-2);
            } else {
              date = "unknown";
            }
            # 3. Print clean output: "nixpkgs: 2026-01-07"
            print name ": " date;
        }
      ')

      count=$(echo -n "$updates" | grep -c '^' || true)

      if [[ -n "$updates" && "$count" -gt 0 ]]; then
        tooltip_esc=$(echo "$updates" | jq -R -s '.')
        printf '{"text":"%s","alt":"has-updates","tooltip":%s}\n' "$count" "$tooltip_esc"
      else
        printf '{"text":"","alt":"updated","tooltip":"System is up to date"}\n'
      fi
    '')

    # ───── 2. THE BUILDER SCRIPT (Click Logic) ─────
    (writeShellScriptBin "waybar-update-builder" ''
      #!/usr/bin/env bash
      set -e

      echo "  Starting System Update..."
      cd "$HOME/.config/nixos"

      # Update the lockfile for real
      nix flake update

      # Commit if changed
      if ! git diff --quiet flake.lock; then
        git add flake.lock
        git commit -m "flake: update inputs ($(date -u +%F))"
        echo "  Flake lockfile updated and committed."
      else
        echo "  No changes in flake inputs."
      fi

      echo "------------------------------------------------"
      echo "🔨 Rebuilding system..."

      # Using nh as in your previous config
      nh os switch

      echo "------------------------------------------------"
      echo "✅ Update complete! You can close this window."
      read -p "Press Enter to exit..."
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
