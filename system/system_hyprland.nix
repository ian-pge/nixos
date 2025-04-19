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
            powerManagement.enable = true;
            powerManagement.finegrained = false;
            open = false;
            nvidiaSettings = true;
            package = config.boot.kernelPackages.nvidiaPackages.latest;
            };
    };

    boot.kernelParams = [ "nvidia-drm.modeset=1" ];

    services = {
        # displayManager.ly.enable = true;

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
            displayManager.gdm.enable = true;
        };
    };

    services.gnome.gnome-keyring.enable = true;
    security.pam.services.login.enableGnomeKeyring = true;
    security.pam.services.hyprlock.enableGnomeKeyring = true;

    networking.wireless.iwd.enable = true;

    programs = {
        hyprland = {
            enable = true;
            withUWSM = true;
            xwayland.enable = true;
        };

        uwsm.enable = true;

        nh = {
            enable = true;
            clean.enable = true;
            clean.extraArgs = "--keep-since 4d --keep 3";
            flake = "/etc/nixos#default";
        };
    };

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
        mako
        swayosd
        waybar
        udiskie
        rofi-wayland
        yazi

    ];
}
