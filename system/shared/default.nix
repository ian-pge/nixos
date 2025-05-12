{inputs, ...}: {
  imports = [
    (import ./disko.nix {device = "/dev/nvme0n1";})

    inputs.disko.nixosModules.default
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.default

    ./hardware-configuration.nix
    ./boot.nix
    ./persistance.nix
    ./nixos_config.nix
    ./docker.nix
    ./qmk_keyboard.nix
    ./steam.nix
    ./nh.nix
    ./ssh.nix
    ./stereolabs.nix
    ./lutris.nix
    ./betaflight.nix
    ./virtualisation.nix
  ];
}
