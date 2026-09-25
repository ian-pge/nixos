{
  lib,
  writeShellApplication,
  quickshell,
  qt6,
}: let
  source = lib.fileset.toSource {
    root = ../../home_manager/quickshell/top-bar;
    fileset = lib.fileset.fileFilter
      (file: file.hasExt "qml" || file.hasExt "js")
      ../../home_manager/quickshell/top-bar;
  };
in
  writeShellApplication {
    name = "quickshell-beeper-preview";
    runtimeInputs = [quickshell];
    text = ''
      export QML_IMPORT_PATH="${qt6.qtmultimedia}/${qt6.qtbase.qtQmlPrefix}''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
      export QT_PLUGIN_PATH="${qt6.qtmultimedia}/${qt6.qtbase.qtPluginPrefix}''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
      exec ${quickshell}/bin/quickshell --path ${source}/beeper-preview.qml "$@"
    '';
    meta = {
      description = "Local Beeper messenger design preview with fictional conversations";
      platforms = lib.platforms.linux;
    };
  }
