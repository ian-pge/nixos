{
  pkgs,
  localPackages,
}:
pkgs.mkShell {
  packages = [
    localPackages.quickshellRuntime
    pkgs.nodejs
    pkgs.jq
    pkgs.dbus
    pkgs.libnotify
    pkgs.qt6.qtdeclarative
  ];

  # Run QML and protocol tests without relying on globally installed tools.
  QMLTESTRUNNER = "${pkgs.qt6.qtdeclarative}/bin/qmltestrunner";
  QT_PLUGIN_PATH = "${pkgs.qt6.qtsvg}/${pkgs.qt6.qtbase.qtPluginPrefix}";
  BEEPER_TEST_BACKEND = "${localPackages.quickshellBeeper}/bin/quickshell-beeper";
}
