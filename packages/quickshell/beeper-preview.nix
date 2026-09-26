{
  lib,
  writeShellApplication,
  quickshellRuntime,
  quickshellDesktop,
}:
writeShellApplication {
  name = "quickshell-beeper-preview";
  runtimeInputs = [quickshellRuntime];
  text = ''
      exec ${quickshellRuntime}/bin/quickshell --path ${quickshellDesktop}/preview.qml "$@"
  '';
  meta = {
    description = "Local Beeper messenger design preview with fictional conversations";
    platforms = lib.platforms.linux;
  };
}
