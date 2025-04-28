{inputs, ...}: {
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence

    ./home_manager.nix
    ./persistance.nix
    ./git
    ./additional_packages
  ];
}
