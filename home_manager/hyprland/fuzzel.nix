{lib, ...}: {
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        dpi-aware = "no";
        use-bold = "yes";
        font = lib.mkForce "Ubuntu Nerd Font:size=20";
        layer = "top";
      };
    };
  };
}
