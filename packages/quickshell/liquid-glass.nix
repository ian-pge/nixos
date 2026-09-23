{
  lib,
  hyprlandPlugins,
  cmake,
  ninja,
  glslang,
  wayland-scanner,
  nodejs,
}:
hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "liquid-glass";
  version = "0.5.0";
  src = lib.fileset.toSource {
    root = ../../tools/liquid-glass;
    fileset = lib.fileset.unions [
      ../../tools/liquid-glass/CMakeLists.txt
      ../../tools/liquid-glass/src
      ../../tools/liquid-glass/shaders
      ../../tools/liquid-glass/protocol
      ../../tools/liquid-glass/tests/curvature-test.mjs
      ../../tools/liquid-glass/tests/pebble-source-test.mjs
      ../../tools/liquid-glass/tests/pebble-fixtures.mjs
      ../../tools/liquid-glass/tests/pebble-fixtures.txt
      ../../tools/liquid-glass/pebble-source.json
      ../../tools/liquid-glass/cushion-source.json
      ../../tools/liquid-glass/tests/cushion-source-test.mjs
      ../../tools/liquid-glass/tests/cushion-fixtures.mjs
      ../../tools/liquid-glass/tests/cushion-fixtures.txt
      ../../tools/liquid-glass/viewer/src/cushion.ts
      ../../tools/liquid-glass/viewer/src/profile.ts
      ../../tools/liquid-glass/viewer/src/pebble.ts
    ];
  };
  nativeBuildInputs = [cmake ninja glslang wayland-scanner nodejs];
  doCheck = true;
  meta = {
    description = "Live refractive backgrounds for the local Quickshell bar";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
  };
}
