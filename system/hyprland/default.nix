{inputs, ...}: {
  imports = [
    inputs.stylix.nixosModules.stylix

    ./home_manager.nix
    ./nvidia.nix
    ./bluetooth.nix
    ./keyring.nix
    ./udisks2.nix
    ./pipewire.nix
    ./greetd.nix
    ./network_manager.nix
    ./zsh.nix
    ./hyprland.nix
    ./fonts.nix
    ./stylix.nix
    ./xdg_termfilechooser.nix
    ./nautilus.nix
  ];
}
