{ config, pkgs, inputs, ... }:

{
    home-manager = {
        extraSpecialArgs = {inherit inputs;};
        backupFileExtension = "backup";
        users = {
            "ian" = import ../home_manager/home_hyprland.nix;
        };
    };

    hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = false;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
    };

    services = {
        displayManager.ly.enable = true;
        xserver = {
            enable = true;
            videoDrivers = ["nvidia"];
        };
    };

    programs.hyprland.enable = true;
    # xdg.portal = {
        # enable = true;
        # extraPortals = [
        # pkgs.xdg-desktop-portal-gtk
        # pkgs.xdg-desktop-portal-hyprland
        # ];
    # };

    # Packages
    environment.systemPackages = with pkgs; [
        # hyprland
        hyprland
        hypridle
        hyprlock
        hyprpaper
        hyprpicker
        hyprshot

        # internet
        iwd
        impala

        # bluetooth
        bluez
        bluetui

        kitty
        ly
        iwd



    ];
}
