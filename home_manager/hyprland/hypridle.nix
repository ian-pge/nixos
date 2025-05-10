{
  ## hypridle itself
  services.hypridle = {
    enable = true; # systemd-user unit :contentReference[oaicite:1]{index=1}

    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      ## multiple listeners become a *list* in Nix
      listener = [
        {
          timeout = 150; # 2.5 min
          "on-timeout" = "brightnessctl -s set 10";
          "on-resume" = "brightnessctl -r";
        }
        {
          timeout = 300; # 5 min
          "on-timeout" = "loginctl lock-session";
        }
        {
          timeout = 1200; # 20 min
          "on-timeout" = "hyprctl dispatch dpms off";
          "on-resume" = "hyprctl dispatch dpms on";
        }
        # {
        #   timeout      = 1800;                              # 30 min
        #   "on-timeout" = "systemctl suspend";
        # }
      ];
    };
  };
}
