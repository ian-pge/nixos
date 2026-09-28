{
  config,
  pkgs,
  ...
}: let
  lock = "${pkgs.procps}/bin/pidof hyprlock >/dev/null || ${config.programs.hyprlock.package}/bin/hyprlock";
  # This desktop uses Hyprland's Lua config/IPC. Legacy `dispatch dpms off`
  # is parsed as invalid Lua, so the timeout fires but never powers down a panel.
  dpms = action: "${config.wayland.windowManager.hyprland.package}/bin/hyprctl dispatch 'hl.dsp.dpms({ action = \"${action}\" })'";
in {
  services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = lock;
        # The greetd/UWSM session is reported as a greeter by logind;
        # `loginctl lock-session` can target a session that rejects locking.
        # Reuse the keyboard's guarded locker command, and wait for the actual
        # Wayland lock before releasing the suspend-delay inhibitor.
        before_sleep_cmd = lock;
        inhibit_sleep = 3;
        after_sleep_cmd = dpms "enable";
      };

      listener = [
        {
          timeout = 150; # 2.5 min
          "on-timeout" = "brightnessctl -s set 10";
          "on-resume" = "brightnessctl -r";
        }
        {
          timeout = 300; # 5 min
          "on-timeout" = lock;
        }
        {
          timeout = 1200; # 20 min
          "on-timeout" = dpms "disable";
          "on-resume" = dpms "enable";
        }
        # {
        #   timeout      = 1800;                              # 30 min
        #   "on-timeout" = "systemctl suspend";
        # }
      ];
    };
  };
}
