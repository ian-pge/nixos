{helpers}: let
  inherit (helpers) mkLuaArgs;
in {
  config = {
    cursor.no_hardware_cursors = true;

    general = {
      gaps_in = 5;
      gaps_out = {
        top = 10;
        right = 10;
        bottom = 10;
        left = 10;
      };
      border_size = 4;
      col = {
        active_border = "rgba(33ff33ff)";
        inactive_border = "rgba(888888aa)";
      };
      resize_on_border = true;
      allow_tearing = false;
      layout = "dwindle";
    };

    decoration = {
      rounding = 10;
      active_opacity = 1.0;
      inactive_opacity = 1.0;
      dim_special = 0.4;
      dim_around = 0.55;
      shadow.enabled = false;
      blur = {
        enabled = true;
        size = 4;
        passes = 2;
        ignore_opacity = true;
      };
    };

    animations.enabled = true;
    dwindle.preserve_split = true;

    misc = {
      focus_on_activate = true;
      force_default_wallpaper = 0;
      disable_hyprland_logo = true;
      disable_splash_rendering = true;
    };

    xwayland.force_zero_scaling = true;

    ecosystem = {
      no_update_news = true;
      no_donation_nag = true;
    };

    input = {
      kb_layout = "us";
      kb_options = "compose:caps";
      follow_mouse = 1;
      sensitivity = 0.8;
      touchpad.natural_scroll = false;
    };
  };

  curve = [
    (mkLuaArgs [
      "quick"
      {
        type = "bezier";
        points = [[0.15 0] [0.1 1]];
      }
    ])
    (mkLuaArgs [
      "easeOutQuint"
      {
        type = "bezier";
        points = [[0.23 1] [0.32 1]];
      }
    ])
    (mkLuaArgs [
      "easeInOutCubic"
      {
        type = "bezier";
        points = [[0.65 0.05] [0.36 1]];
      }
    ])
    (mkLuaArgs [
      "linear"
      {
        type = "bezier";
        points = [[0 0] [1 1]];
      }
    ])
    (mkLuaArgs [
      "almostLinear"
      {
        type = "bezier";
        points = [[0.5 0.5] [0.75 1.0]];
      }
    ])
  ];

  animation = [
    {
      leaf = "windows";
      enabled = true;
      speed = 7;
      bezier = "default";
      style = "popin";
    }
    {
      leaf = "border";
      enabled = false;
    }
    {
      leaf = "fade";
      enabled = true;
      speed = 4;
      bezier = "default";
    }
    {
      leaf = "workspaces";
      enabled = true;
      speed = 6;
      bezier = "default";
      style = "slide";
    }
    {
      leaf = "specialWorkspace";
      enabled = true;
      speed = 6;
      bezier = "default";
      style = "slidevert";
    }
    {
      leaf = "layers";
      enabled = true;
      speed = 6;
      bezier = "default";
      style = "fade";
    }
  ];
}
