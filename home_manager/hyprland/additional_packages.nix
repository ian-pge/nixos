{pkgs, ...}: {
  home.packages = with pkgs; [
    oh-my-posh
    hyprpicker
    hyprshot
    bluetui
    wl-clipboard
    vlc
    nvtopPackages.full
    adwaita-icon-theme
    catppuccin-cursors.macchiatoDark
    # nautilus
    nmap
    wl-clipboard-rs
  ];

  services.swayosd.enable = true;
  services.udiskie.enable = true;
  programs.yazi.enable = true;
  services.playerctld.enable = true;
  services.hypridle.enable = true;
  programs.hyprlock.enable = true;
  services.hyprpolkitagent.package = true;
  programs.htop.enable = true;
  programs.obs-studio.enable = true;
  programs.bat.enable = true;
}
