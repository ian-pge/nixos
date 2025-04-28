{
  inputs,
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

  environment.systemPackages = with pkgs; [
    xdg-desktop-portal-termfilechooser
  ];
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-termfilechooser
    ];
    config.common = {
      default = ["hyprland"];
      "org.freedesktop.impl.portal.FileChooser" = ["termfilechooser"];
    };
  };
  # ---- make the portal launch Ghostty ----
  environment.variables.TERMCMD = "${pkgs.ghostty}/bin/ghostty --app-id file_chooser";
}
