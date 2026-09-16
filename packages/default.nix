{
  inputs,
  pkgs,
}: let
  tabctl = pkgs.callPackage ./tabctl.nix {src = inputs.tabctl;};
in
  {
    inherit tabctl;
    hyprlockAge = pkgs.callPackage ./hyprlock-age.nix {};
    quickshellChromeTabs = pkgs.callPackage ./quickshell/chrome-tabs.nix {inherit tabctl;};
    quickshellBrightness = pkgs.callPackage ./quickshell/brightness.nix {};
    quickshellNixCleaner = pkgs.callPackage ./quickshell/nix-cleaner.nix {};
    quickshellSystemStats = pkgs.callPackage ./quickshell/system-stats.nix {};
    quickshellSpeedtest = pkgs.callPackage ./quickshell/speedtest.nix {};
    quickshellGpuMonitor = pkgs.callPackage ./quickshell/gpu-monitor.nix {};
    quickshellWeather = pkgs.callPackage ./quickshell/weather.nix {};
  }
  // import ./quickshell/update.nix {inherit pkgs;}
