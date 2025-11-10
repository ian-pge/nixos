{pkgs, ...}: {
  home.packages = with pkgs; [
    hyprpicker
    hyprshot
    bluetui
    gazelle-tui
    vlc
    nvtopPackages.full
    adwaita-icon-theme
    catppuccin-cursors.macchiatoDark
    nmap
    nettools
    wl-clipboard
    ncdu
    nurl
    brightnessctl
    jq
    gnome-disk-utility
    viu
    # oculante
    seahorse
    gcalcli
    aichat
    pulsemixer
  ];

  services.swayosd.enable = true;
  services.udiskie.enable = true;
  services.playerctld.enable = true;
  services.hyprpolkitagent.package = true;
  programs.htop.enable = true;
  programs.bat.enable = true;
  programs.fd.enable = true;
  programs.fzf.enable = true;
}
