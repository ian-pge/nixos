{pkgs, ...}: {
  programs.lutris.enable = true;
  home.packages = with pkgs; [protonup-qt];
}
