{inputs, ...}: {
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak

    ./home_manager.nix
    ./git.nix
    ./additional_packages.nix
    # ./mime_apps.nix
    ./zed.nix

    ./razer.nix

    # ./bambustudio.nix
  ];
}
