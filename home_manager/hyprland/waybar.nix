{pkgs, ...}: {
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    ## Main bar configuration ─ straight conversion of your JSON
    settings = {
      mainBar = {
        layer = "top";
        output = "eDP-1";

        modules-left = [
          "custom/launcher"
          "disk"
          "cpu"
          "custom/gpu"
          "memory"
          "custom/nixos"
        ];

        modules-center = ["hyprland/workspaces"];

        modules-right = [
          "bluetooth"
          "network"
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
          format = " {:%H:%M}";
          timezone = "Europe/Paris";
          tooltip = false;
        };
        "clock#second" = {
          format = " {:%b %d %Y}";
          tooltip = false;
        };

        ## ───── System modules ─────
        cpu = {
          interval = 5;
          format = " {usage}%";
          on-click = "ghostty -e htop";
        };

        memory = {
          interval = 5;
          format = "  {}%";
          "on-click" = "ghostty -e htop";
        };

        "custom/gpu" = {
          exec = "waybar-gpu-nvidia";
          interval = 5;
          format = "  {text}";
          tooltip = true;
          return-type = "json";
          on-click = "ghostty -e nvtop";
        };

        backlight = {
          format = "{icon} {percent}%";
          "format-icons" = [
            "󱩎"
            "󱩏"
            "󱩐"
            "󱩑"
            "󱩒"
            "󱩓"
            "󱩔"
            "󱩕"
            "󱩖"
            "󰛨"
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
          format-ethernet = "󰈀 {ifname}";
          format-disconnected = "󰤭 Disconnected";
          format-disabled = "󰤭 Off";
          format-disabled-if-down = true;
          tooltip-format = "{ifname} via {gwaddr}";
          on-click = "ghostty -e nmtui";
        };

        "custom/launcher" = {
          format = "";
          on-click = "pgrep -x fuzzel >/dev/null 2>&1 || fuzzel";
          tooltip = false;
        };

        "custom/nixos" = {
          exec = "waybar-update-checker";
          interval = 3600;
          tooltip = true;
          return-type = "json";
          format = "{icon}{}";
          format-icons = {
            "has-updates" = "";
            "updated" = "";
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
          format = " {percentage_used}%";
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
          font-size: 19px;
      }

      window#waybar {
          background: none;
      }

      #clock, #cpu, #memory, #backlight, #custom-gpu,
      #wireplumber, #network, #bluetooth, #custom-nixos,
      #upower, #disk, #workspaces, #custom-launcher {
          background-color: @crust;
          border-radius: 10px;
          padding: 2px 10px;
          margin: 8.5px 4px;
          font-size: 19px;
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
      #workspaces button.active{ color: #33ccff; }
    '';
  };

  home.packages = with pkgs; [
    jq # we’ll let jq escape & join lines for us

    (writeShellScriptBin "waybar-gpu-nvidia" ''
      #!/usr/bin/env bash
      set -euo pipefail
      export NO_COLOR=1

      # Try to read util%, temp °C, used MiB, total MiB
      if ! IFS=',' read -r util temp mem_used mem_total < <(
             nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total \
                        --format=csv,noheader,nounits 2>/dev/null | head -n1
           ) || [ -z "$mem_total" ] || [ "$mem_total" -eq 0 ]; then
        printf '{"text":"0%% 0%%","alt":"gpu-off","tooltip":"\"GPU offline\""}\n'
        exit 0
      fi

      # VRAM % rounded
      vram_pct=$(awk -v u="$mem_used" -v t="$mem_total" \
                     'BEGIN { printf "%d", (u*100 + t/2)/t }')

      # used VRAM GiB with one decimal
      mem_gib=$(awk -v u="$mem_used" 'BEGIN { printf "%.1f", u/1024 }')

      tooltip=$(printf '%s GiB used' "$mem_gib" | jq -Rsa .)

      printf '{"text":"%s%% %s%%","alt":"gpu","tooltip":%s}\n' \
             "$util" "$vram_pct" "$tooltip"
    '')

    (writeShellScriptBin "waybar-update-checker" ''
      #!/usr/bin/env bash
      #
      # Waybar module: count packages that would change after bumping nixpkgs,
      #                without fetching substitutes or building anything.
      #
      set -euo pipefail
      export NO_COLOR=1                      # nix‑diff → monochrome

      flake_dir="/etc/nixos"                 # system flake location

      # 1. ── work in a throw‑away copy so we never touch the real repo ─────────
      scratch="$(mktemp -d)"
      trap 'rm -rf "$scratch"' EXIT
      rsync -a --exclude='.git' "$flake_dir/" "$scratch" >/dev/null
      cd "$scratch"

      # 2. ── update nixpkgs input in the *scratch* lock file (quietly) ─────────
      nix flake update nixpkgs --quiet    # modern flag

      # 3. ── ask Nix for the next system’s *derivation* only (pure eval) ──────
      next_drv=$(nix eval --raw \
        ".#nixosConfigurations.$HOSTNAME.config.system.build.toplevel.drvPath")

      # 4. ── get the derivation of the running system (modern sub‑command) ────
      cur_drv=$(nix derivation show /run/current-system | jq -r 'keys[0]')

      # 5. ── identical hashes ⇒ system already up to date ─────────────────────
      if [[ "$next_drv" == "$cur_drv" ]]; then
        printf '{"text":"","alt":"updated","tooltip":"System up‑to‑date"}\n'
        exit 0
      fi

      # 6. run nix‑diff (no --brief), count bullet lines for the number
      diff=$(nix run nixpkgs#nix-diff -- /run/current-system "$next_drv")
      changes=$(printf "%s\n" "$diff" | grep -c '^[[:space:]]*•' || true)
      tooltip=$(printf "%s\n" "$diff" | jq -Rsa .)   # JSON‑escape for Waybar

      printf '{"text":" %s","alt":"has-updates","tooltip":%s}\n' \
             "$changes" "$tooltip"
    '')
  ];
}
