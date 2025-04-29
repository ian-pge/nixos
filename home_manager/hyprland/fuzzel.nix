{
  programs.fuzzel = {
    enable = true;
    settings = {
      output = "eDP-1";
      main = {
        dpi-aware = "yes";
        layer = "overlay";
      };
    };
  };
}
