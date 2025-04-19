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
        };
    };

    # services.displayManager.sddm.wayland.enable = true;

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


        uwsm = {
            enable = true;
            waylandCompositors = {
              hyprland = {
                prettyName = "Hyprland (UWSM)";
                comment = "Hyprland compositor managed by UWSM";
                binPath = "${pkgs.hyprland}/bin/Hyprland";
              };
            };
          };

        nh = {
            enable = true;
            clean.enable = true;
            clean.extraArgs = "--keep-since 4d --keep 3";
            flake = "/etc/nixos";
        };
    };








    ## greetd + tuigreet
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            # fallback if tuigreet fails (TTY autologin)
            command = "${pkgs.agreety}/bin/agreety --cmd ${pkgs.bash}/bin/bash";
            user    = "root";
          };

          default_session = {
            user    = "greeter";   # greetd’s dedicated user
            command = ''
              ${pkgs.greetd.tuigreet}/bin/tuigreet                       \
                --time --remember --user-menu                            \
                --cmd "uwsm start -- hyprland.desktop"               \
                --sessions /run/current-system/sw/share/wayland-sessions \
                --sessions /etc/profiles/per-user/%u/share/wayland-sessions
            '';
          };
        };

    # greeter user – minimal shell, no password
    users.users.greeter = {
        isSystemUser = true;
        group = "greeter";
        home  = "/var/lib/greeter";
        shell = pkgs.nologin;
    };
    users.groups.greeter = { };










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
