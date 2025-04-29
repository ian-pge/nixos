{pkgs, ...}: {
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    theme = /home/ian/rofi/config.rasi;
    extraConfig = {
      modi = "drun,window";
      show-icons = true;
    };
  };
}
