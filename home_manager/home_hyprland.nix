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
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };

    # Tells GTK 3 to prefer a dark theme variant
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  programs.kitty.enable = true;

  wayland.windowManager.hyprland = {
    enable = true;
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
          "$fileManager"  = "kitty -e yazi";
          "$menu"         = "pgrep -x rofi >/dev/null 2>&1 || .config/rofi/launchers/type-4/launcher.sh";
          "$editor"       = "zeditor";

          ### AUTOSTART ###
          "exec-once" = [
            "hyprpaper"
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
            "4, monitor:HDMI-A-1"
            "5, monitor:HDMI-A-1"
            "6, monitor:HDMI-A-1"
          ];

          ### ENVIRONMENT ###
          env = [
            "EDITOR,zeditor"
            "XDG_CURRENT_DESKTOP,Hyprland"
            "TERMINAL,kitty"
            "BROWSER,zen-browser"
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
            border_size       = 2;
            "col.active_border"   = "rgba(33ccffee)";
            "col.inactive_border" = "rgba(33ccffee)";
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
            # per‑device example
            "device:epic-mouse-v1".sensitivity = -0.5;
          };

          gestures.workspace_swipe = true;

          ### KEYBINDINGS ###
          "$mainMod" = "SUPER";

          binde = [
            ",XF86AudioRaiseVolume,exec,swayosd-client --output-volume=raise"
            ",XF86AudioLowerVolume,exec,swayosd-client --output-volume=lower"
          ];
          bind = [
            ",XF86AudioMute,exec,swayosd-client --output-volume mute-toggle"
            ",XF86AudioPlay,exec,playerctl play-pause"
            ",XF86AudioNext,exec,playerctl next"
            ",XF86AudioPrev,exec,playerctl previous"
            ",PRINT,exec,hyprshot -m region -o ~/Screenshots"
            "$mainMod,RETURN,exec,$terminal"
            "$mainMod,W,killactive"
            "$mainMod CONTROL,Q,exit"
            "$mainMod,P,pseudo"
            "$mainMod,F,exec,$fileManager"
            "$mainMod,A,exec,$menu"
            "$mainMod,Z,togglesplit"
            "$mainMod,G,exec,zen-browser"
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
            "$mainMod,mouse:272,movewindow"
            "$mainMod,mouse:273,resizewindow"
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

      # optional, but keeps $EDITOR & friends for shells spawned outside Hyprland
      home.sessionVariables = {
        EDITOR               = "zeditor";
        XDG_CURRENT_DESKTOP  = "Hyprland";
        XDG_SESSION_TYPE     = "wayland";
      };
}
