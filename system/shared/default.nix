{inputs, overlays, ...}: {
  # Apply local package overlays anywhere the shared system module is imported,
  # including specialisations with inheritParentConfig = false.
  nixpkgs.overlays = builtins.attrValues overlays;

  imports = [
    (import ./disko.nix {device = "/dev/nvme0n1";})

    inputs.disko.nixosModules.default
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.default
    inputs.nix-flatpak.nixosModules.nix-flatpak

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
  ];
}
