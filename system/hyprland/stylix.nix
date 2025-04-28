{pkgs, ...}: {
  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-macchiato.yaml";
    autoEnable = false;
    fonts.monospace = {
      name = "Hack Nerd Font";
      package = pkgs.nerd-fonts.hack;
    };
  };
}
