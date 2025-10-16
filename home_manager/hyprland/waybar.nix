{pkgs, ...}: {
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
        };

        network = {
          format-wifi = "{icon} {essid}";
          format-icons = ["󰤟" "󰤢" "󰤥" "󰤨"];
          interval = 5;
          format-ethernet = "󰈀 {ifname}";
          format-disconnected = "󰤭 Disconnected";
          format-disabled = "󰤭 Off";
          format-disabled-if-down = true;
          tooltip-format = "{ifname} via {gwaddr}";
          on-click = "ghostty -e 'nmcli device wifi list; exec fish'";
        };

        "custom/launcher" = {
          format = "";
          on-click = "pgrep -x fuzzel >/dev/null 2>&1 || fuzzel";
          tooltip = false;
        };

        "custom/nixos" = {
          exec = "waybar-update-checker";
          interval = 5;
          on-click = "ghostty -e waybar-update-builder &";
          # signal = 8;
          return-type = "json";
          tooltip = true;
          format = "{icon}{text}";
          format-icons = {
            error = "";
            busy = ""; # spinner     (while building)
            has-updates = ""; # circular arrows
            updated = ""; # check mark
            outdated = "";
          };
        };

        bluetooth = {
          format = "󰂲 Disconnected";
          format-connected = "󰂯 {device_alias}";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          format-off = "󰂲 Off";
          on-click = "ghostty -e bluetui";
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
      #upower, #disk, #workspaces, #custom-launcher {
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

      #workspaces button       { color: @text; background: none; border: none; }
      #workspaces button:hover { background: none; }
      #workspaces button.active{ color: #33ff33; }
    '';
  };

  home.packages = with pkgs; [
    (writeShellScriptBin "waybar-update-checker" ''
      #!/usr/bin/env bash
      set -uo pipefail                      # keep it simple: no -e, no traps

      flake_lock="$HOME/.config/nixos/flake.lock"
      branch="nixpkgs-unstable"            # sensible fallback

      # ── current revision ────────────────────────────────────────────
      if [[ -f $flake_lock ]]; then
        cur_rev=$(jq -er '.nodes.nixpkgs.locked.rev' "$flake_lock" 2>/dev/null || true)
        branch=$(jq -er '.nodes.nixpkgs.original.ref // empty' "$flake_lock" 2>/dev/null || echo "$branch")
      else
        cur_rev=""
      fi

      # ── latest revision  ───────────────────
      latest_rev=$(
        timeout 30s \
          nix flake metadata --json "github:NixOS/nixpkgs?ref=$branch" 2>/dev/null |
        jq -er '.locked.rev' 2>/dev/null || true
      )

      # ── single decision point ──────────────────────────────────────
      if [[ -z $cur_rev || -z $latest_rev ]]; then
        printf '{"text":"","alt":"error","tooltip":"Error"}\n'
      elif [[ $cur_rev == "$latest_rev" ]]; then
        printf '{"text":"","alt":"updated","tooltip":"System up-to-date"}\n'
      else
        printf '{"text":"","alt":"outdated","tooltip":"System outdated"}\n'
      fi
    '')

    (writeShellScriptBin "waybar-update-builder" ''
      #!/usr/bin/env bash
      set -euo pipefail

      cd "$HOME/.config/nixos"

      nix flake update

      # Only commit if something changed
      if ! git diff --quiet flake.lock; then
        git add flake.lock
        git commit -m "flake: update inputs ($(date -u +%F))"
        git push
      fi

      nh os switch
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
}
