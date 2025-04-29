{pkgs, ...}: {
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    theme = /rofi/config.rasi;
    extraConfig = {
      modi = "drun,window";
      show-icons = true;
    };
  };
}
