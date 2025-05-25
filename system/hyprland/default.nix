{inputs, ...}: {
  imports = [
    inputs.catppuccin.nixosModules.catppuccin

    ./home_manager.nix
    ./nvidia.nix
    ./bluetooth.nix
    ./keyring.nix
    ./udisks2.nix
    ./pipewire.nix
    ./greetd.nix
    ./network_manager.nix
    # ./zsh.nix
    ./fish.nix
    ./hyprland.nix
    ./fonts.nix
    ./catppuccin.nix
    # ./xdg_portal.nix
    # ./nautilus.nix
    ./upower.nix
    ./xdg_mime.nix
  ];
}
