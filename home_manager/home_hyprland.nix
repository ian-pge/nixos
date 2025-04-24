{ pkgs, ... }:

{
  imports = [
    ./home.nix
  ];

  # Enable dconf to manage GNOME settings
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";  # Preferred color scheme
      gtk-theme = "Adwaita-dark";    # Set GTK theme to Adwaita-dark
    };
  };

  # Configure GTK settings
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    cursorTheme = {
      name = "catppuccin-macchiato-dark-cursors";
      package = pkgs.catppuccin-cursors.macchiatoDark;
    };

    # Tells GTK 3 to prefer a dark theme variant
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  services.hyprpaper = {
        enable  = true;                   # turn on the hyprpaper service
        settings = {
          ipc      = "off";                # enable fast IPC mode for live changes
          preload  = [ "/etc/nixos/material/wallpaper.png" ];   # images to load at startup
          wallpaper = [ ",/etc/nixos/material/wallpaper.png" ]; # apply to all monitors
        };
      };

  programs.kitty = {
    enable = true;
    themeFile = "Catppuccin-Macchiato";
    font = {
          name    = "UbuntuMono Nerd Font";
          size    = 12;
    };
    shellIntegration = {
        enableZshIntegration = true;
        # mode = "no-cursor";
    };
    settings = {
          window_padding_width = "5 5";
          cursor_blinking       = true;              #
          # cursor_blink_interval = 0.5;               #
          cursor_shape          = "block";           #
          # cursor_trail          = 100;               #
  };


  };

  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false;
    systemd.variables = ["--all"];
    portalPackage = null;
    package = null;
    # Additional Hyprland configurations can go here
    #
    settings = {

          ### MONITORS ###
          monitor = [
            "eDP-1,2560x1600@165,0x0,1"
            "HDMI-A-1,2560x1440@144,0x-1440,1"
          ];

          ### VARIABLES ###
          "$terminal"     = "kitty";
          "$browser"      = "google-chrome-stable";
          "$fileManager"  = "kitty -e yazi";
          "$menu"         = "pgrep -x rofi >/dev/null 2>&1 || .config/rofi/launchers/type-4/launcher.sh";
          "$editor"       = "zeditor";

          ### AUTOSTART ###
          "exec-once" = [
            "hyprpaper"
            "uwsm finalize"
            "systemctl --user start hyprpolkitagent"
            "mako"
            "swayosd-server"
            "udiskie &"
            "xhost +local:"
            "hypridle"
            "waybar"
          ];

          ### STATIC WORKSPACES ###
          workspace = [
            "1, monitor:eDP-1"
            "2, monitor:eDP-1"
            "3, monitor:eDP-1"
            "4, monitor:eDP-1"
            "5, monitor:HDMI-A-1"
            "6, monitor:HDMI-A-1"
            "7, monitor:HDMI-A-1"
            "8, monitor:HDMI-A-1"
          ];

          ### ENVIRONMENT ###
          env = [
            "ZVM_INIT_MODE,sourcing"
            "HYPRCURSOR_THEME,catppuccin-macchiato-dark-cursors"
            "HYPRCURSOR_SIZE,24"
            "XCURSOR_THEME,catppuccin-macchiato-dark-cursors"
            "XCURSOR_SIZE,24"
            "EDITOR,zeditor"
            "TERMINAL,kitty"
            "BROWSER,google-chrome-stable"
            "GTK_USE_PORTAL,1"
            "ELECTRON_OZONE_PLATFORM_HINT,wayland"
            # NVIDIA tweaks
            "LIBVA_DRIVER_NAME,nvidia"
            "XDG_SESSION_TYPE,wayland"
            "GBM_BACKEND,nvidia-drm"
            "__GLX_VENDOR_LIBRARY_NAME,nvidia"
          ];

          ### CURSOR ###
          cursor.no_hardware_cursors = true;

          ### GENERAL LOOK‑AND‑FEEL ###
          general = {
            gaps_in           = 5;
            gaps_out          = 10;
            border_size       = 3;
            "col.active_border"   = "rgba(33ccffee)";
            "col.inactive_border" = "rgba(888888aa)";
            resize_on_border  = true;
            allow_tearing     = false;
            layout            = "dwindle";
          };

          decoration = {
            rounding         = 10;
            active_opacity   = 1.0;
            inactive_opacity = 1.0;
            blur = {
              enabled        = true;
              size           = 4;
              passes         = 2;
              ignore_opacity = true;
            };
          };

          animations.enabled = true;
          bezier            = [ "myBezier,0.05,0.9,0.1,1.05" ];
          animation         = [
            "windows,1,7,myBezier,popin"
            "border,1,10,default"
            "fade,1,4,default"
            "workspaces,1,6,default,slide"
            "layers,0.5,6,default,fade"
          ];

          dwindle = {
            pseudotile     = true;
            preserve_split = true;
          };

          misc = {
            force_default_wallpaper = 0;
            disable_hyprland_logo   = true;
            disable_splash_rendering = true;
          };

          ### INPUT ###
          input = {
            kb_layout     = "us";
            kb_options    = "compose:caps";
            follow_mouse  = 1;
            sensitivity   = 0.8;
            touchpad.natural_scroll = false;
          };

          gestures.workspace_swipe = true;

          ### KEYBINDINGS ###
          "$mainMod" = "SUPER";

          binde = [
            ",XF86AudioRaiseVolume,exec,swayosd-client --output-volume=raise"
            ",XF86AudioLowerVolume,exec,swayosd-client --output-volume=lower"
            ",XF86MonBrightnessUp,exec,swayosd-client --brightness=raise"
            ",XF86MonBrightnessDown,exec,swayosd-client --brightness=lower"
          ];
          bind = [
            ",XF86AudioPlay,exec,playerctl play-pause"
            ",XF86AudioNext,exec,playerctl next"
            ",XF86AudioPrev,exec,playerctl previous"
            ",XF86AudioMute,exec,swayosd-client --output-volume=mute-toggle"
            ",PRINT,exec,hyprshot -m region -o ~/Screenshots"
            "$mainMod,RETURN,exec,$terminal"
            "$mainMod,W,killactive"
            "$mainMod CONTROL,Q,exit"
            "$mainMod,P,pseudo"
            "$mainMod,F,exec,$fileManager"
            "$mainMod,A,exec,$menu"
            "$mainMod,E,exec,$editor"
            "$mainMod,Z,togglesplit"
            "$mainMod,G,exec,$browser"
            "$mainMod,H,movefocus,l" "$mainMod,L,movefocus,r"
            "$mainMod,K,movefocus,u" "$mainMod,J,movefocus,d"
            "$mainMod SHIFT,H,movewindow,l" "$mainMod SHIFT,L,movewindow,r"
            "$mainMod SHIFT,K,movewindow,u" "$mainMod SHIFT,J,movewindow,d"
            "$mainMod,SPACE,fullscreen,1" "$mainMod SHIFT,SPACE,fullscreen,0"
            "$mainMod,C,exec,hyprlock"
            "$mainMod CONTROL,h,resizeactive,-50 0"
            "$mainMod CONTROL,j,resizeactive,0 50"
            "$mainMod CONTROL,k,resizeactive,0 -50"
            "$mainMod CONTROL,l,resizeactive,50 0"
            # workspaces 1‑6 (focus)
            "$mainMod,1,workspace,1" "$mainMod,2,workspace,2" "$mainMod,3,workspace,3"
            "$mainMod,4,workspace,4" "$mainMod,5,workspace,5" "$mainMod,6,workspace,6"
            # move to workspace
            "$mainMod SHIFT,1,movetoworkspace,1"
            "$mainMod SHIFT,2,movetoworkspace,2"
            "$mainMod SHIFT,3,movetoworkspace,3"
            "$mainMod SHIFT,4,movetoworkspace,4"
            "$mainMod SHIFT,5,movetoworkspace,5"
            "$mainMod SHIFT,6,movetoworkspace,6"
            # scratchpads
            "$mainMod,S,togglespecialworkspace,LLM"
            "$mainMod SHIFT,S,movetoworkspace,special:LLM"
            "$mainMod,D,togglespecialworkspace,Chat"
            "$mainMod SHIFT,D,movetoworkspace,special:Chat"
            # mouse‑drag
            # "$mainMod,mouse:272,movewindow"
            # "$mainMod,mouse:273,resizewindow"
            # lock
            "$mainMod,ESCAPE,exec,hyprlock"
          ];
          bindm = [
            "$mainMod,mouse:272,movewindow"
            "$mainMod,mouse:273,resizewindow"
          ];

          ### WINDOW / LAYER RULES ###
          windowrulev2 = [
            "workspace special:Chat,title:^(WhatsApp Web)$"
            "workspace special:Chat,title:^(Mattermost)$"
            "workspace special:Chat,title:^(Spotify)$"
            "workspace special:LLM,title:^(Perplexity)$"
            "workspace special:LLM,title:^(ChatGPT)$"
            "tile,class:Google-chrome"
          ];
          layerrule = [
            "blur,rofi"
            "blur,logout_dialog"
          ];
        };
    };

    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    programs.bat = {
      enable = true;
    };

    # Activate Home Manager's ZSH integration
    programs.zsh = {
        sessionVariables = {
        LANG = "en_US.UTF-8";
        };
        enable = true;
        enableCompletion = true;
        # plugins = [
        #       { name = "zsh-vi-mode";
        #         src  = pkgs.zsh-vi-mode;                           # ships in nixpkgs
        #         file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
        #       }
        #       { name = "fast-syntax-highlighting";
        #         src  = pkgs.zsh-fast-syntax-highlighting;
        #         file = "share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh";
        #       }
        #       { name = "zsh-autosuggestions";
        #         src  = pkgs.zsh-autosuggestions;
        #         file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
        #       }
        #       { name = "zsh-history";                # package lives under pkgs
        #         src  = pkgs.zsh-history;
        #         file = "share/zsh/init.zsh";
        #       }
        #       { name = "fzf-tab";
        #         src  = pkgs.zsh-fzf-tab;
        #         file = "share/fzf-tab/fzf-tab.plugin.zsh";
        #       }
        #     ];
    };

    programs.oh-my-posh = {
        enable = true;
        enableZshIntegration = true;
        settings =  {
            "palette" = {
              "blue"      = "#8AADF4";
              "closer"    = "p:os";
              "green"     = "#a6da95";
              "lavender"  = "#B7BDF8";
              "mauve"     = "#c6a0f6";
              "os"        = "#ACB0BE";
              "peach"     = "#F5A97F";
              "pink"      = "#F5BDE6";
              "sapphire"  = "#7dc4e4";
              "yellow"    = "#eed49f";
              "sky"       = "#91d7e3";
            };
            "transient_prompt" = {
              "template"   = "{{now | date \"15:04\"}} ";
              "foreground" = "p:yellow";
              "background" = "transparent";
            };
            "blocks" = [
              {
                "type"      = "prompt";
                "alignment" = "left";
                "newline"   = true;
                "segments" = [
                  {
                    "template"   = "{{.Icon}}  ";
                    "foreground" = "p:sky";
                    "type"       = "os";
                    "style"      = "plain";
                  }
                  {
                    "template"   = "{{.UserName }}@{{ .HostName }} ";
                    "foreground" = "p:blue";
                    "type"       = "session";
                    "style"      = "plain";
                  }
                  {
                    "properties" = {
                      "folder_icon" = "..\ue5fe..";
                      "home_icon"   = "~";
                      "style"       = "agnoster_full";
                    };
                    "template"   = "{{ .Path }} ";
                    "foreground" = "p:pink";
                    "type"       = "path";
                    "style"      = "plain";
                  }
                  {
                    "properties" = {
                      "branch_icon"          = "\ue725 ";
                      "cherry_pick_icon"     = "\ue29b ";
                      "commit_icon"          = "\uf417 ";
                      "fetch_status"         = false;
                      "fetch_upstream_icon"  = false;
                      "merge_icon"           = "\ue727 ";
                      "no_commits_icon"      = "\uf0c3 ";
                      "rebase_icon"          = "\ue728 ";
                      "revert_icon"          = "\uf0e2 ";
                      "tag_icon"             = "\uf412 ";
                    };
                    "template"   = "{{ .HEAD }} ";
                    "foreground" = "p:lavender";
                    "type"       = "git";
                    "style"      = "plain";
                  }
                ];
              }
              {
                "type"      = "prompt";
                "alignment" = "left";
                "newline"   = true;
                "segments" = [
                  {
                    "template"             = "❯";
                    "type"                 = "text";
                    "style"                = "plain";
                    "foreground_templates" = [
                      "{{if gt .Code 0}}red{{end}}"
                      "{{if eq .Code 0}}green{{end}}"
                    ];
                  }
                ];
              }
              {
                "type"      = "rprompt";
                "alignment" = "right";
                "segments" = [
                  {
                    "properties" = {
                      "always_enabled" = true;
                      "style"          = "round";
                    };
                    "template"   = "{{ .FormattedMs }} ";
                    "foreground" = "p:peach";
                    "type"       = "executiontime";
                    "style"      = "plain";
                  }
                ];
              }
            ];
            "version"     = 3;
            "final_space" = true;
          };
    };





    programs.waybar = {
        enable = true;

        ## Main bar configuration ─ straight conversion of your JSON
        settings = {
        mainBar = {
            layer           = "top";
            "output"        = "eDP-1";

            "modules-left"  = [
            "custom/launcher"  "disk" "cpu" "memory"
            "custom/gpu" "custom/nixos"
            ];

            "modules-center" = [ "hyprland/workspaces" ];

            "modules-right"  = [
            "bluetooth" "network" "upower" "pulseaudio"
            "backlight" "clock#second" "clock"
            ];

            ## ───── Hyprland workspaces ─────
            "hyprland/workspaces" = {
            "active-only"         = false;
            "all-outputs"         = true;
            "show-special"        = true;
            "special-visible-only"= true;
            format                = "{icon}";
            "format-icons" = {
                "1" = "1"; "2" = "2"; "3" = "3"; "4" = "4"; "5" = "5";
                "special:llm" = "S1";
                "special:multimedia" = "S2";
            };
            };

            ## ───── Clocks ─────
            clock = {
            format   = " {:%H:%M}";
            timezone = "Europe/Paris";
            tooltip  = false;
            };
            "clock#second" = {
            format  = " {:%b %d %Y}";
            tooltip = false;
            };

            ## ───── System modules ─────
            cpu = {
            interval = 5;
            format   = " {usage}%";
            "on-click" = "kitty htop";
            };

            memory = {
            interval = 5;
            format   = "  {}%";
            "on-click" = "kitty htop";
            };

            "custom/gpu" = {
            format        = "{icon} {0}";
            exec          = "gpu-usage-waybar";
            "return-type" = "json";
            "format-icons"= "";
            "on-click"    = "kitty nvtop";
            };

            backlight = {
            format        = "{icon} {percent}%";
            "format-icons"= [ "󱩎" "󱩏" "󱩐" "󱩑" "󱩒"
                                "󱩓" "󱩔" "󱩕" "󱩖" "󰛨" ];
            tooltip = false;
            };

            pulseaudio = {
            format        = "{icon} {volume}%";
            "format-muted"= "󰖁";
            "format-icons".default = [ "󰕿" "󰖀" "󰕾" ];
            "on-click"    = "kitty pulsemixer";
            };

            network = {
            "format-wifi"       = "{icon} {essid}";
            "format-icons"      = [ "󰤟" "󰤢" "󰤥" "󰤨" ];
            "format-ethernet"   = "󰈀 {ifname}";
            "format-disconnected" = "󰤭 Disconnected";
            "format-disabled"     = "󰤭 Off";
            "format-disabled-if-down" = true;
            tooltip-format          = "{ifname} via {gwaddr}";
            "on-click"              = "kitty impala";
            };

            "custom/launcher" = {
            format   = "";
            "on-click"= "pgrep -x rofi >/dev/null 2>&1 || .config/rofi/launchers/type-4/launcher.sh";
            tooltip  = false;
            };


            "custom/nixos"= {
                "exec"= "$HOME/bin/update-checker";
                "on-click"= "$HOME/bin/update-checker && notify-send 'The system has been updated'";
                "interval"= 3600;
                "tooltip"= true;
                "return-type"= "json";
                "format"= "{} {icon}";
                "format-icons"= {
                    "has-updates"= "";
                    "updated"= "";
                };
            };


            bluetooth = {
            format                     = "󰂲 Disconnected";
            "format-connected"         = "󰂯 {device_alias}";
            tooltip-format             = "{controller_alias}\t{controller_address}";
            "tooltip-format-connected" = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
            "tooltip-format-enumerate-connected" = "{device_alias}\t{device_address}";
            "format-off"               = "󰂲 Off";
            "on-click"                 = "kitty bluetui";
            };

            upower = {
            "icon-size"    = 20;
            format         = " {percentage}";
            "hide-if-empty"= true;
            tooltip        = true;
            "tooltip-spacing" = 20;
            "on-click"     = "kitty sudo powertop";
            };

            disk = {
            interval  = 30;
            format    = " {percentage_used}%";
            path      = "/";
            "on-click"= "kitty sudo ncdu -x /";
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

        * {
            font-family: "Ubuntu Nerd Font";
            font-size: 19px;
        }

        window#waybar {
            background-color: @crust;
            color: #ffffff;
        }

        #clock, #cpu, #memory, #backlight, #custom-gpu,
        #pulseaudio, #network, #bluetooth, #custom-nixos,
        #upower, #disk, #workspaces, #custom-launcher {
            color: #e5e5e5;
            background-color: @base;
            border-radius: 8px;
            padding: 2px 10px;
            margin: 8.5px 4px;
            font-size: 18.5px;
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
