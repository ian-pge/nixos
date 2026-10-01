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
    # Qt/FFmpeg's VAAPI/CUDA video path can hang both the scene-graph and GUI
    # threads on this NVIDIA/Wayland setup (vaExportSurfaceHandle failures).
    # A comma is Qt's documented, unambiguous empty HW decoder list.
    # Decode media on the CPU while keeping Qt Quick/Liquid Glass GPU rendering.
    # Qt's WebP decoder lives in qtimageformats: messenger stickers and
    # many chat photos are static or animated WebP.
    # Qt's SVG image plugin renders the provider logos and application icons.
    wrapProgram "$out/bin/quickshell" \
      --set-default QT_FFMPEG_DECODING_HW_DEVICE_TYPES "," \
      --prefix QML_IMPORT_PATH : "${liquidGlassClient}/lib/qt-6/qml:${qt6.qtmultimedia}/${qt6.qtbase.qtQmlPrefix}" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtmultimedia}/${qt6.qtbase.qtPluginPrefix}:${qt6.qtimageformats}/${qt6.qtbase.qtPluginPrefix}:${qt6.qtsvg}/${qt6.qtbase.qtPluginPrefix}"
    ln -sfn quickshell "$out/bin/qs"
  '';
}
