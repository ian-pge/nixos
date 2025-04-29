{
  inputs,
  lib,
  pkgs,
  ...
}: {
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
    ./nautilus.nix
  ];
  xdg.portal = {
    enable = lib.mkForce true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-termfilechooser
    ];
    config.common = {
      "org.freedesktop.impl.portal.FileChooser" = ["termfilechooser"];
    };
  };
}
