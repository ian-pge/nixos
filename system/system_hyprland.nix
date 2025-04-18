{ config, pkgs, inputs, ... }:

{
    home-manager = {
        extraSpecialArgs = {inherit inputs;};
        backupFileExtension = "backup";
        users = {
            "ian" = import ../home_manager/home_hyprland.nix;
        };
    };

    hardware = {
        # Enable OpenGL
        graphics.enable = true;

        bluetooth = {
            enable = true;
            powerOnBoot = true;
        };

        nvidia = {
            modesetting.enable = true;
            powerManagement.enable = false;
            powerManagement.finegrained = false;
            open = false;
            nvidiaSettings = true;
            package = config.boot.kernelPackages.nvidiaPackages.stable;
            };
    };

    services = {
        displayManager.ly.enable = true;

        pipewire = {
            wireplumber.enable = true;
            enable = true;
            alsa = {
                enable = true;
                support32Bit = true;
            };
            pulse.enable = true;
            jack.enable = true;
        };

        xserver = {
            enable = true;
            videoDrivers = ["nvidia"];
        };
    };

    networking.wireless.iwd.enable = true;

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
        hypridle
        hyprlock
        hyprpaper
        hyprpicker
        hyprshot

        # networking tui
        impala
        bluetui

        kitty
        ly



    ];
}
