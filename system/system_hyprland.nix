{ config, pkgs, inputs, lib, ... }:

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
            enable = false;
            videoDrivers = ["nvidia"];
        };
    };

    services.gnome.gnome-keyring.enable = true;
    security.pam.services.login.enableGnomeKeyring = true;
    security.pam.services.hyprlock.enableGnomeKeyring = true;

    networking.wireless.iwd.enable = true;

    fonts.packages = with pkgs; [
        nerd-fonts.ubuntu
        nerd-fonts.ubuntu-mono
        nerd-fonts.ubuntu-sans
    ];

    programs = {
        hyprland = {
            enable = true;
            withUWSM = true;
            xwayland.enable = true;
        };
    };

    services.greetd = {
        enable = true;                  # start greetd daemon
        vt     = 1;                     # run on tty1
        settings = {
          default_session = {
            # tuigreet binary from nixpkgs
            command =
            lib.concatStringsSep " " [
                "${pkgs.greetd.tuigreet}/bin/tuigreet"
                "--remember"
                "--width" "40"
                "--time"
                "--asterisks"
                "--theme" "'border=magenta;prompt=green;time=yellow;container=black;input=cyan'"
              ];
            user = "greeter"; # unprivileged greeter user
          };
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
        mako
        swayosd
        waybar
        udiskie
        rofi-wayland
        yazi
        greetd.tuigreet
        greetd.greetd
        acpi
        acpid
        vlc

    ];
}
