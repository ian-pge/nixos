{ config, pkgs, inputs, ... }:

{
    programs.fuse.userAllowOther = true;
    home-manager = {
        extraSpecialArgs = {inherit inputs;};
        backupFileExtension = "backup";
        users = {
        "ian" = import ../home_manager/home.nix;
        };
    };

    # Load nvidia driver for Xorg and Wayland
    services.xserver.videoDrivers = ["nvidia"];

    hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = false;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    # Packages
    environment.systemPackages = with pkgs; [
        hyprland
        ly
    ];

    programs.hyprland.enable = true;
    xdg.portal = {
        enable = true;
        extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-hyprland
        ];
    };
    # You might want a display manager for Hyprland
    services.displayManager.ly.enable = true;
}
