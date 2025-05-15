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
          exec = "env LD_LIBRARY_PATH='/run/opengl-driver/lib' gpu-usage-waybar";
          format = "{icon} {}";
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
          on-click = "waybar-update-checker";
          return-type = "json";
          tooltip = true;
          format = "{icon} {}";
          format-icons = {
            "busy" = "";
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
    (writeShellScriptBin "waybar-update-checker" ''
      #!/usr/bin/env bash
      set -euo pipefail
      export NO_COLOR=1

      printf '{"text":"...","alt":"busy","tooltip":"Building ..."}\n'

      flake_dir="/etc/nixos"
      scratch="$(mktemp -d)"
      trap 'rm -rf "$scratch"' EXIT

      rsync -a --exclude='.git' "$flake_dir/" "$scratch" >/dev/null 2>&1
      cd "$scratch"

      # modern command; send **all** noise to /dev/null
      nix flake update --update-input nixpkgs >/dev/null 2>&1

      nix build ".#nixosConfigurations.$HOSTNAME.config.system.build.toplevel" \
                --no-link --out-link result-new >/dev/null 2>&1

      updates=$(nvd diff /run/current-system ./result-new | grep -c '\[U' || true)

      if [ "$updates" -eq 0 ]; then
        printf '{"text":"0","alt":"updated","tooltip":"System up‑to‑date"}\n'
        exit 0
      fi

      # Build tooltip, let jq handle escaping *and* newline → \n conversion
      tooltip=$(nvd diff /run/current-system ./result-new \
                  | grep '\[U' \
                  | awk '{for(i=3;i<NF;i++)printf $i" "; print $NF}' \
                  | jq -Rsa .)                 # gives a JSON string literal

      # tooltip already has quotes; don’t wrap again
      printf '{"text":"%s","alt":"has-updates","tooltip":%s}\n' \
              "$updates" "$tooltip"
    '')

    /*
    ── gpu‑usage‑waybar built on‑the‑fly ─────────────
    */
    (rustPlatform.buildRustPackage {
      pname = "gpu-usage-waybar";
      version = "0.1.23"; # latest release, 3 May 2025 :contentReference[oaicite:0]{index=0}

      src = fetchFromGitHub {
        # pulls the exact crate published to crates.io
        owner = "PolpOnline";
        repo = "gpu-usage-waybar";
        rev = "0.1.23";
        hash = "sha256-DUIKiUgTy4jn8NZZvjC0zuA993Sbq1Fvr7tvJw3+tNw="; # first run with lib.fakeSha256, copy real hash
      };

      # Cargo.lock lives in the repo, so just grab the hashes once:
      cargoHash = "sha256-X3Ak0K1kt7++tE7qZgy8GaRzqemUNTJ3z1yGBJZyA4s=";
      doCheck = false; # upstream has no tests yet :contentReference[oaicite:1]{index=1}
    })
  ];
}
