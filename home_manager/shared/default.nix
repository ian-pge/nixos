{inputs, ...}: {
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence

    ./home_manager.nix
    ./persistance.nix
    ./git.nix
    ./additional_packages.nix
    ./mime_apps.nix
    ./zed.nix
  ];
}
