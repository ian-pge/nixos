{
  pkgs,
  localPackages,
  ...
}: let
  topBarConfig =
    pkgs.runCommand "quickshell-top-bar" {
      nativeBuildInputs = [pkgs.qt6Packages.qtshadertools];
    } ''
      cp -R ${./quickshell/top-bar} "$out"
      chmod -R u+w "$out"
      qsb --qt6 \
        -o "$out/shaders/activity-border.frag.qsb" \
        "$out/shaders/activity-border.frag"
    '';
in {
  home.packages = with localPackages; [
    quickshellUpdateChecker
    quickshellUpdateDiff
    quickshellUpdateInstaller
    quickshellNixCleaner
    quickshellBrightness
    quickshellSystemStats
    quickshellGpuMonitor
    quickshellWeather
    quickshellSpeedtest
  ];

  programs.quickshell = {
    enable = true;

    configs.top-bar = topBarConfig;
    activeConfig = "top-bar";

    systemd = {
      enable = true;
      target = "graphical-session.target";
    };
  };

  # Qt otherwise selects the single-threaded basic render loop on this
  # NVIDIA/Wayland setup, making high-refresh QML animations visibly uneven.
  systemd.user.services.quickshell = {
    Unit.X-Restart-Triggers = ["${topBarConfig}"];
    Service.Environment = ["QSG_RENDER_LOOP=threaded"];
  };
}
