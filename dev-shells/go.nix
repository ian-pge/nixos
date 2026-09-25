{pkgs}:
pkgs.mkShell {
  packages = with pkgs; [
    go
    gopls
    delve
    golangci-lint
  ];
}
