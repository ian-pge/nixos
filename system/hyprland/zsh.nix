{pkgs, ...}: {
  programs.zsh.enable = true;

  services.gvfs.enable = true;

  users.defaultUserShell = pkgs.zsh;
}
