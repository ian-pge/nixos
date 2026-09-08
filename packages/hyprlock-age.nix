{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "hyprlock-age";
  version = "0.1.0";

  src = ../tools/hyprlock-age;

  cargoLock.lockFile = ../tools/hyprlock-age/Cargo.lock;

  meta = {
    description = "Render a fractional age for Hyprlock";
    license = lib.licenses.mit;
    mainProgram = "hyprlock-age";
    platforms = lib.platforms.linux;
  };
}
