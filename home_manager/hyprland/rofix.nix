{pkgs, ...}: {
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    # theme = ./rofi/launcher.rasi; # optional
    extraConfig = {
      modi = "drun,window";
      show-icons = true;
    };
  };
}
