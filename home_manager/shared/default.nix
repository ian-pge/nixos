{inputs, ...}: {
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak

    ./home_manager.nix
    ./chezmoi.nix
    ./git.nix
    ./additional_packages.nix
    ./paper-desktop.nix
    # ./mime_apps.nix
    ./zed.nix
  ];

}
