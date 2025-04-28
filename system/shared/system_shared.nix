{inputs, ...}: {
  imports = [
    (import ./disko.nix {device = "/dev/nvme0n1";})

    inputs.disko.nixosModules.default
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.default

    ./hardware-configuration.nix

    ./config/boot.nix
    ./config/persistance.nix
    ./config/nixos_config.nix
    ./config/docker.nix
    ./config/qmk_keyboard.nix
    ./config/steam.nix
    ./config/nh.nix
    ./config/ssh.nix
    ./config/stereolabs.nix
  ];
}
