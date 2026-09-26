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

  # Qt otherwise selects the single-threaded basic render loop on this
  # NVIDIA/Wayland setup, making high-refresh QML animations visibly uneven.
  systemd.user.services.quickshell = {
    Unit.X-Restart-Triggers = ["${localPackages.quickshellDesktop}"];
    Service.Environment = ["QSG_RENDER_LOOP=threaded"];
  };
}
