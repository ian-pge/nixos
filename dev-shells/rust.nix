{pkgs}:
pkgs.mkShell {
  packages = with pkgs; [
    cargo
    clippy
    pkg-config
    rust-analyzer
    rustc
    rustfmt
  ];
}
