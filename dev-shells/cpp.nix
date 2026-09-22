{pkgs}:
# Plugins exchange C++ objects with Hyprland: use its compiler and dependency
# set, rather than nixpkgs' default stdenv (which can use a different GCC).
(pkgs.mkShell.override {stdenv = pkgs.hyprland.stdenv;}) {
  packages = with pkgs; [
    cmake
    ninja
    pkg-config
    clang-tools
    glslang
    # Isolated compositor integration tests and their screenshots.
    nodejs
    grim
    wayland-scanner
  ];

  # Match the inputs used by nixpkgs' mkHyprlandPlugin builder. Adding the
  # package itself also makes its dev output available to pkg-config.
  buildInputs = [pkgs.hyprland pkgs.qt6.qtbase pkgs.qt6.qtdeclarative] ++ pkgs.hyprland.buildInputs;

  CMAKE_EXPORT_COMPILE_COMMANDS = "ON";

  # Ask the pinned compiler for its system headers instead of letting clangd's
  # Nix wrapper inject the default GCC's (potentially older) C++ library.
  CLANGD_FLAGS = "--query-driver=${pkgs.hyprland.stdenv.cc}/bin/*";
}
