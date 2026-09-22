{
  pkgs,
  localPackages,
  ...
}: let
  quickshellWithGlass = pkgs.symlinkJoin {
    name = "quickshell-with-glass-geometry";
    meta.mainProgram = "quickshell";
    paths = [pkgs.quickshell];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram "$out/bin/quickshell" --prefix QML_IMPORT_PATH : "${localPackages.liquidGlassClient}/lib/qt-6/qml"
      ln -sfn quickshell "$out/bin/qs"
    '';
  };
  topBarConfig = pkgs.runCommand "quickshell-top-bar" {} ''
    cp -R ${./quickshell/top-bar} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/StatusData.qml" \
      --replace-fail '"quickshell-system-stats"' '"${localPackages.quickshellSystemStats}/bin/quickshell-system-stats"'
    substituteInPlace "$out/WeatherData.qml" \
      --replace-fail '"quickshell-weather"' '"${localPackages.quickshellWeather}/bin/quickshell-weather"'
    substituteInPlace "$out/AudioAvailability.qml" \
      --replace-fail '"pw-dump"' '"${pkgs.pipewire}/bin/pw-dump"'
    substituteInPlace "$out/NotificationData.qml" \
      --replace-fail '"pw-play"' '"${pkgs.pipewire}/bin/pw-play"' \
      --replace-fail '"/run/current-system/sw/share/sounds/freedesktop/stereo/message-new-instant.oga"' \
        '"${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/message-new-instant.oga"'
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
    package = quickshellWithGlass;

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
