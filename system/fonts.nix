{pkgs, ...}: {
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.hack
    nerd-fonts.ubuntu
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = ["Ubuntu Nerd Font"];
    monospace = ["JetBrainsMono Nerd Font"];
  };
}
