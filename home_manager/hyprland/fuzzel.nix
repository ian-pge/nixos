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
        icon-theme = "Papirus-Dark";
        image-size-ratio = "0.5";
      };
    };
  };
}
