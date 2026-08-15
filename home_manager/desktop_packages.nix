{pkgs, ...}: {
  home.packages = with pkgs; [
    hyprpicker
    hyprshot
    bluetui
    # gazelle-tui
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
    oculante
    seahorse
    pulsemixer
    hyprpaper
  ];

  services.udiskie.enable = true;
  services.playerctld.enable = true;
  # Quickshell owns the session Polkit agent so authentication prompts can be
  # rendered inside the central capsule.
  services.hyprpolkitagent.enable = false;
  programs.htop.enable = true;
  programs.bat.enable = true;
  programs.fd.enable = true;
  programs.fzf.enable = true;
}
