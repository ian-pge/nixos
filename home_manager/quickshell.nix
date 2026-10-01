{localPackages, ...}: {
  home.packages = with localPackages; [
    quickshellUpdateChecker
    quickshellUpdateDiff
    quickshellUpdateInstaller
    quickshellNixCleaner
    quickshellBrightness
    quickshellBeeper
    quickshellSystemStats
    quickshellGpuMonitor
    quickshellWeather
    quickshellSpeedtest
  ];

  programs.quickshell = {
    enable = true;
    package = localPackages.quickshellRuntime;

    configs.top-bar = localPackages.quickshellDesktop;
    activeConfig = "top-bar";

    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
  };

  # Live previews can temporarily point this generated config straight into
  # the store. Let activation reclaim this one path instead of treating the
  # preview symlink as an unmanaged file collision.
  xdg.configFile."quickshell/top-bar".force = true;

  # Qt otherwise selects the single-threaded basic render loop on this
  # NVIDIA/Wayland setup, making high-refresh QML animations visibly uneven.
  systemd.user.services.quickshell = {
    Unit = {
      X-Restart-Triggers = ["${localPackages.quickshellDesktop}"];
      # WantedBy starts the shell, but does not stop it at logout. Without
      # PartOf, it can survive `uwsm stop` connected to the old compositor,
      # and the next login sees an already-running (but invisible) service.
      PartOf = ["graphical-session.target"];
    };
    Service.Environment = ["QSG_RENDER_LOOP=threaded"];
  };
}
