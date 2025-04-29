{lib, ...}: {
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        dpi-aware = "no";
        use-bold = "yes";
        font = lib.mkForce "Ubuntu Nerd Font:size=20";
        keyboard-focus = "on-demand";
        exit-on-keyboard-focus-loss = "no";
        layer = "overlay";
        icon-theme = "Adwaita";
      };
      colors = {
        background = lib.mkForce "000000aa";
      };
    };
  };
}
