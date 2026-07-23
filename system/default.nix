{inputs, overlays, ...}: {
  # Apply local package overlays to the system configuration.
  nixpkgs.overlays = builtins.attrValues overlays;

  imports = [
    (import ./disko.nix {device = "/dev/nvme0n1";})

    inputs.disko.nixosModules.default
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.default
    inputs.nix-flatpak.nixosModules.nix-flatpak
    inputs.catppuccin.nixosModules.catppuccin

    ./hardware-configuration.nix
    ./boot.nix
    ./persistance.nix
    ./nixos_config.nix
    ./docker.nix
    ./qmk_keyboard.nix
    # ./steam.nix
    ./nh.nix
    ./ssh.nix
    ./stereolabs.nix
    # ./lutris.nix
    ./betaflight.nix
    ./virtualisation.nix
    ./tailscale.nix
    ./flatpak.nix
    ./appimage.nix
    ./razer.nix
    ./home_manager.nix
    ./nvidia.nix
    ./bluetooth.nix
    ./keyring.nix
    ./udisks2.nix
    ./pipewire.nix
    ./greetd.nix
    ./network_manager.nix
    # ./zsh.nix
    ./avahi.nix
    ./fish.nix
    ./hyprland.nix
    ./fonts.nix
    ./catppuccin.nix
    ./xdg_portal.nix
    ./nautilus.nix
    ./upower.nix
    ./xdg_mime.nix
    # ./typing_booster.nix
  ];
}
