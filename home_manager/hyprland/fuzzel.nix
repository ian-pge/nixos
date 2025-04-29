{lib, ...}: {
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        dpi-aware = "no";
        use-bold = "yes";
        font = lib.mkForce "Ubuntu Nerd Font:size=20";
        layer = "overlay";
        icon-theme = "Adwaita";
        image-size-ratio = "1";
      };
      colors = {
        background = lib.mkForce "000000aa";
      };
    };
  };
}
