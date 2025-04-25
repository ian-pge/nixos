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

    security.pam.services.greetd.enableGnomeKeyring = true;
    security.pam.services.hyprlock.enableGnomeKeyring = true;
    security.pam.services.login.enableGnomeKeyring = true;

    networking = {
      useDHCP = false;             # NM will do DHCP itself
      networkmanager = {
        enable = true;
        # wifi.backend = "iwd";      # make NM talk to iwd instead of wpa_supplicant
      };
    };

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

      services.udisks2.enable = true;

      programs.zsh.enable = true;
      users.defaultUserShell = pkgs.zsh;


    # Packages
    environment.systemPackages = with pkgs; [
        # hyprland
        hypridle
        hyprlock
        hyprpaper
        hyprpicker
        hyprshot
        hyprpolkitagent
        hyprcursor

        bluetui

        # zsh plugins
        zsh-fast-syntax-highlighting
        zsh-autosuggestions
        bat
        zsh-vi-mode
        zsh-fzf-tab
        fzf
        zsh-vi-mode


        kitty
        mako
        swayosd
        waybar
        udiskie
        rofi-wayland
        yazi
        greetd.tuigreet
        greetd.greetd
        playerctl
        vlc
        htop
        nvtopPackages.full
        adwaita-icon-theme
        catppuccin-cursors.macchiatoDark
        oh-my-posh
        nautilus
        nmap
        obs-obs-studio
        peek

    ];
}
