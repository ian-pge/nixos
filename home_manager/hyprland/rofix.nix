{
  pkgs,
  config,
  ...
}: {
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    theme = "${config.xdg.configHome}/rofi/config.rasi";
    extraConfig = {
      modi = "drun,window";
      show-icons = true;
    };
  };
}
