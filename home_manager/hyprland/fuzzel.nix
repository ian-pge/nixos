{
  programs.fuzzel = {
    enable = true;
    settings = {
      output = "DP-1";
      main = {
        dpi-aware = "yes";
        layer = "overlay";
      };
    };
  };
}
