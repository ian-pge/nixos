{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.stylix.nixosModules.stylix

    ./home_manager
    ./nvidia
    ./bluetooth.nix
    ./keyring.nix
    ./udisks2.nix
    ./pipewire.nix
    ./greetd.nix
    ./network_manager.nix
    ./zsh.nix
    ./hyprland/zsh.nix
    ./fonts.nix
    ./stylix.nix
  ];

  environment.systemPackages = with pkgs; [
    # hyprland
    hypridle
    hyprlock
    hyprpaper
    hyprpicker
    hyprshot
    hyprpolkitagent
    hyprcursor

    # other
    bluetui
    wl-clipboard
    mako
    swayosd
    waybar
    udiskie
    rofi-wayland
    yazi
    playerctl
    vlc
    htop
    nvtopPackages.full
    adwaita-icon-theme
    catppuccin-cursors.macchiatoDark
    nautilus
    nmap
    obs-studio
  ];
}
