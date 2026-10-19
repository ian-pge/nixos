{pkgs}:
pkgs.mkShell {
  packages = with pkgs; [
    cargo
    clippy
    dbus
    pkg-config
    rust-analyzer
    rustc
    rustfmt
  ];
}
