# nix eval --file home_manager/tests/hypridle_test.nix
# Pure configuration checks: never lock a session or change a real display.
let
  module = import ../hypridle.nix {
    pkgs.procps = "/test/procps";
    config = {
      programs.hyprlock.package = "/test/hyprlock";
      wayland.windowManager.hyprland.package = "/test/hyprland";
    };
  };
  settings = module.services.hypridle.settings;
  dim = builtins.elemAt settings.listener 0;
  lock = builtins.elemAt settings.listener 1;
  screens = builtins.elemAt settings.listener 2;
  # Keep a single shell argument around the Lua expression. No monitor selector
  # means both the internal panel and every external display are targeted.
  dpmsOn = "/test/hyprland/bin/hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
  dpmsOff = "/test/hyprland/bin/hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
in
assert module.services.hypridle.enable;
assert map (listener: listener.timeout) settings.listener == [150 300 1200];
assert dim.on-timeout == "brightnessctl -s set 10";
assert dim.on-resume == "brightnessctl -r";
assert screens.on-timeout == dpmsOff;
assert screens.on-resume == dpmsOn;
assert settings.general.after_sleep_cmd == dpmsOn;
assert lock.on-timeout == settings.general.lock_cmd;
assert settings.general.before_sleep_cmd == settings.general.lock_cmd;
assert settings.general.lock_cmd == "/test/procps/bin/pidof hyprlock >/dev/null || /test/hyprlock/bin/hyprlock";
assert settings.general.inhibit_sleep == 3;
# Do not work around a broken command by ignoring legitimate movie/presentation
# inhibitors, or by putting the entire computer to sleep instead of its screens.
assert !(settings.general.ignore_dbus_inhibit or false);
assert !(settings.general.ignore_systemd_inhibit or false);
assert !(settings.general.ignore_wayland_inhibit or false);
assert builtins.all (listener: !(listener.ignore_inhibit or false)) settings.listener;
true
