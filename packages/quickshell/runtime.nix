{
  symlinkJoin,
  makeWrapper,
  quickshell,
  qt6,
  liquidGlassClient,
}:
symlinkJoin {
  name = "quickshell-with-glass-geometry";
  meta.mainProgram = "quickshell";
  paths = [quickshell];
  nativeBuildInputs = [makeWrapper];
  postBuild = ''
    wrapProgram "$out/bin/quickshell" \
      --prefix QML_IMPORT_PATH : "${liquidGlassClient}/lib/qt-6/qml:${qt6.qtmultimedia}/${qt6.qtbase.qtQmlPrefix}" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtmultimedia}/${qt6.qtbase.qtPluginPrefix}"
    ln -sfn quickshell "$out/bin/qs"
  '';
}
