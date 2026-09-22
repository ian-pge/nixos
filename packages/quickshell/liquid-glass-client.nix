{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  wayland,
  wayland-scanner,
  qt6,
}:
stdenv.mkDerivation {
  pname = "liquid-glass-client";
  version = "0.2.0";
  src = lib.fileset.toSource {
    root = ../../tools/liquid-glass;
    fileset = lib.fileset.unions [../../tools/liquid-glass/client ../../tools/liquid-glass/protocol];
  };
  cmakeDir = "../client";
  nativeBuildInputs = [cmake ninja pkg-config wayland-scanner qt6.wrapQtAppsHook];
  buildInputs = [wayland qt6.qtbase qt6.qtdeclarative];
  dontWrapQtApps = true;
  meta = {
    description = "Frame-synchronous capsule geometry for Quickshell Liquid Glass";
    license = lib.licenses.mit;
  };
}
