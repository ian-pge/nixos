{
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    ## Main bar configuration ─ straight conversion of your JSON
    settings = {
      mainBar = {
        layer = "top";
        "output" = "eDP-1";

        "modules-left" = [
          "custom/launcher"
          "disk"
          "cpu"
          "memory"
          "custom/gpu"
          "custom/nixos"
        ];

        "modules-center" = ["hyprland/workspaces"];

        "modules-right" = [
          "bluetooth"
          "network"
          "upower"
          "pulseaudio"
          "backlight"
          "clock#second"
          "clock"
        ];

        ## ───── Hyprland workspaces ─────
        "hyprland/workspaces" = {
          "active-only" = false;
          "all-outputs" = true;
          "show-special" = true;
          "special-visible-only" = true;
          format = "{icon}";
          "format-icons" = {
            "1" = "1";
            "2" = "2";
            "3" = "3";
            "4" = "4";
            "5" = "5";
            "6" = "6";
            "7" = "7";
            "8" = "8";
            "special:llm" = "S1";
            "special:multimedia" = "S2";
          };
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
          "on-click" = "ghostty htop";
        };

        memory = {
          interval = 5;
          format = "  {}%";
          "on-click" = "ghostty htop";
        };

        "custom/gpu" = {
          format = "{icon} {0}";
          exec = "gpu-usage-waybar";
          "return-type" = "json";
          "format-icons" = "";
          "on-click" = "ghostty nvtop";
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

        pulseaudio = {
          format = "{icon} {volume}%";
          "format-muted" = "󰖁";
          "format-icons".default = ["󰕿" "󰖀" "󰕾"];
          "on-click" = "ghostty pulsemixer";
        };

        network = {
          "format-wifi" = "{icon} {essid}";
          "format-icons" = ["󰤟" "󰤢" "󰤥" "󰤨"];
          "format-ethernet" = "󰈀 {ifname}";
          "format-disconnected" = "󰤭 Disconnected";
          "format-disabled" = "󰤭 Off";
          "format-disabled-if-down" = true;
          tooltip-format = "{ifname} via {gwaddr}";
          "on-click" = "ghostty impala";
        };

        "custom/launcher" = {
          format = "";
          "on-click" = "pgrep -x rofi >/dev/null 2>&1 || .config/rofi/launchers/type-4/launcher.sh";
          tooltip = false;
        };

        "custom/nixos" = {
          "exec" = "$HOME/bin/update-checker";
          "on-click" = "$HOME/bin/update-checker && notify-send 'The system has been updated'";
          "interval" = 3600;
          "tooltip" = true;
          "return-type" = "json";
          "format" = "{} {icon}";
          "format-icons" = {
            "has-updates" = "";
            "updated" = "";
          };
        };

        bluetooth = {
          format = "󰂲 Disconnected";
          "format-connected" = "󰂯 {device_alias}";
          tooltip-format = "{controller_alias}\t{controller_address}";
          "tooltip-format-connected" = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          "tooltip-format-enumerate-connected" = "{device_alias}\t{device_address}";
          "format-off" = "󰂲 Off";
          "on-click" = "ghostty bluetui";
        };

        upower = {
          "icon-size" = 20;
          format = " {percentage}";
          "hide-if-empty" = true;
          tooltip = true;
          "tooltip-spacing" = 20;
          "on-click" = "ghostty sudo powertop";
        };

        disk = {
          interval = 30;
          format = " {percentage_used}%";
          path = "/";
          "on-click" = "ghostty sudo ncdu -x /";
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
      #pulseaudio, #network, #bluetooth, #custom-nixos,
      #upower, #disk, #workspaces, #custom-launcher {
          background-color: @crust;
          border-radius: 10px;
          padding: 2px 10px;
          margin: 8.5px 4px;
          font-size: 19px;
      }

      #cpu            { color: @pink;      }
      #memory         { color: @green;     }
      #custom-gpu     { color: @mauve;     }
      #backlight      { color: @yellow;    }
      #network        { color: @maroon;    }
      #pulseaudio     { color: @lavender;  }
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
}
