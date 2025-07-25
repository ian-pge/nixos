{
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false;
    systemd.variables = ["--all"];

    settings = {
      ### MONITORS ###
      monitor = [
        "DP-2,5120x2160@120,0x0,1.25"
        "eDP-1,2560x1600@165,-2048x448,1.25"
      ];

      ### VARIABLES ###
      "$terminal" = "ghostty";
      "$browser" = "google-chrome-stable";
      "$fileManager" = "ghostty --title=File -e yazi";
      "$calculator" = "ghostty --title=Calculator -e kalker";
      "$menu" = "pgrep -x fuzzel >/dev/null 2>&1 || fuzzel";
      "$editor" = "zeditor";

      ### AUTOSTART ###
      "exec-once" = [
        "uwsm finalize"
        "xhost +local:"
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
        "HYPRCURSOR_THEME,catppuccin-macchiato-dark-cursors"
        # "HYPERSHOT_DIR,~/Pictures/"
        "HYPRCURSOR_SIZE,24"
        "XCURSOR_THEME,catppuccin-macchiato-dark-cursors"
        "XCURSOR_SIZE,24"
        "EDITOR,zeditor"
        "TERMINAL,ghostty"
        "BROWSER,google-chrome-stable"
        "GTK_USE_PORTAL,1"
        "NIXOS_XDG_OPEN_USE_PORTAL,1"
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
        gaps_in = 5;
        gaps_out = "10,10,10,10";
        border_size = 3;
        "col.active_border" = "rgba(33ff33ff)";
        "col.inactive_border" = "rgba(888888aa)";
        resize_on_border = true;
        allow_tearing = false;
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
        active_opacity = 1.0;
        inactive_opacity = 1.0;
        blur = {
          enabled = true;
          size = 4;
          passes = 2;
          ignore_opacity = true;
        };
      };

      animations.enabled = true;
      bezier = [
        "quick,0.15,0,0.1,1"
        "easeOutQuint,0.23,1,0.32,1"
        "easeInOutCubic,0.65,0.05,0.36,1"
        "linear,0,0,1,1"
        "almostLinear,0.5,0.5,0.75,1.0"
      ];

      animation = [
        "windows,1,7,default,popin"
        "border,0"
        "fade,1,4,default"
        "workspaces,1,6,default,slide"
        "layers,0.5,6,default,fade"
      ];

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      ecosystem = {
        no_update_news = true;
        no_donation_nag = true; # again, optional
      };

      ### INPUT ###
      input = {
        kb_layout = "us";
        kb_options = "compose:caps";
        follow_mouse = 1;
        sensitivity = 0.8;
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
        ",PRINT,exec,hyprshot -m region -o ~/Pictures/Screenshots"
        "$mainMod,RETURN,exec,$terminal"
        "$mainMod,W,killactive"
        "$mainMod CONTROL,Q,exit"
        "$mainMod,P,pseudo"
        "$mainMod,F,exec,$fileManager"
        "$mainMod,A,exec,$menu"
        "$mainMod,E,exec,$editor"
        "$mainMod,Z,togglesplit"
        "$mainMod,G,exec,$browser"
        "$mainMod,X,exec,$calculator"
        "$mainMod,H,movefocus,l"
        "$mainMod,L,movefocus,r"
        "$mainMod,K,movefocus,u"
        "$mainMod,J,movefocus,d"
        "$mainMod SHIFT,H,movewindow,l"
        "$mainMod SHIFT,L,movewindow,r"
        "$mainMod SHIFT,K,movewindow,u"
        "$mainMod SHIFT,J,movewindow,d"
        "$mainMod,SPACE,fullscreen,1"
        "$mainMod SHIFT,SPACE,fullscreen,0"
        "$mainMod CONTROL,h,resizeactive,-50 0"
        "$mainMod CONTROL,j,resizeactive,0 50"
        "$mainMod CONTROL,k,resizeactive,0 -50"
        "$mainMod CONTROL,l,resizeactive,50 0"
        # workspaces 1‑6 (focus)
        "$mainMod,1,workspace,1"
        "$mainMod,2,workspace,2"
        "$mainMod,3,workspace,3"
        "$mainMod,4,workspace,4"
        "$mainMod,5,workspace,5"
        "$mainMod,6,workspace,6"
        "$mainMod,7,workspace,7"
        "$mainMod,8,workspace,8"
        # move to workspace
        "$mainMod SHIFT,1,movetoworkspace,1"
        "$mainMod SHIFT,2,movetoworkspace,2"
        "$mainMod SHIFT,3,movetoworkspace,3"
        "$mainMod SHIFT,4,movetoworkspace,4"
        "$mainMod SHIFT,5,movetoworkspace,5"
        "$mainMod SHIFT,6,movetoworkspace,6"
        "$mainMod SHIFT,7,movetoworkspace,7"
        "$mainMod SHIFT,8,movetoworkspace,8"
        # scratchpads
        "$mainMod,S,togglespecialworkspace,LLM"
        "$mainMod SHIFT,S,movetoworkspace,special:LLM"
        "$mainMod,D,togglespecialworkspace,Chat"
        "$mainMod SHIFT,D,movetoworkspace,special:Chat"
        "$mainMod,C,togglespecialworkspace,Media"
        "$mainMod SHIFT,C,movetoworkspace,special:Media"
        "$mainMod,V,togglespecialworkspace,Notes"
        "$mainMod SHIFT,V,movetoworkspace,special:Notes"
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
        "workspace special:Chat,title:^(Gmail)$"
        "workspace special:Chat,title:^(Messenger)$"
        "workspace special:Media,title:^(Spotify)$"
        "workspace special:LLM,title:^(ChatGPT)$"
        "workspace special:Notes,title:^(Google Keep)$"
        "float,title:^(Calculator)$"
        "size 400 500,title:^(Calculator)$"
        "center,title:^(Calculator)$"
        "float,title:^(File)$"
        "size 1000 600,title:^(File)$"
        "center,title:^(File)$"
      ];
      layerrule = [
        "dimaround,launcher"
      ];
    };
  };
}
