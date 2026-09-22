{
  lib,
  hyprlandPlugins,
  cmake,
  ninja,
  glslang,
  wayland-scanner,
}:
hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "liquid-glass";
  version = "0.2.3";
  src = lib.fileset.toSource {
    root = ../../tools/liquid-glass;
    fileset = lib.fileset.unions [
      ../../tools/liquid-glass/CMakeLists.txt
      ../../tools/liquid-glass/src
      ../../tools/liquid-glass/shaders
      ../../tools/liquid-glass/protocol
    ];
  };
  nativeBuildInputs = [cmake ninja glslang wayland-scanner];
  doCheck = true;
  meta = {
    description = "Live refractive backgrounds for the local Quickshell bar";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
  };
}
