{pkgs, ...}: {
  xdg.configFile."BeeperTexts/custom.css" = {
    source = ./catppuccin-macchiato.css;
    force = true;
  };

  # Beeper's public local API is served by Desktop. Its native minimized-on-launch
  # preference suppresses the startup window; the silent Hyprland rule is only
  # a fallback. Keep the native preferences in the persistent user profile.
  systemd.user.services.beeper = {
    Unit = {
      Description = "Beeper Desktop — local messaging API";
      Documentation = ["https://developers.beeper.com/desktop-api/"];
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
      ConditionEnvironment = "WAYLAND_DISPLAY";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "exec";
      # Match the existing beepertexts.desktop launcher supplied by nixpkgs.
      ExecStart = "${pkgs.beeper}/bin/beeper --no-sandbox";
      Restart = "on-failure";
      RestartSec = "5s";
      Slice = "app-graphical.slice";
      UMask = "0077";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
