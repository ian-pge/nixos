{inputs, ...}: {
  imports = [
    inputs.stylix.nixosModules.stylix
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
    # ./stylix.nix
    ./catppuccin.nix
    ./xdg_termfilechooser.nix
    ./nautilus.nix
  ];
}
