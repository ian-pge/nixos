{
  config,
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    inputs.stylix.nixosModules.stylix
  ];

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

  boot.kernelParams = ["nvidia-drm.modeset=1"];

  services = {
    udisks2.enable = true;
    gnome.gnome-keyring.enable = true;
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
    greetd = {
      enable = true; # start greetd daemon
      vt = 1; # run on tty1
      settings = {
        default_session = {
          # tuigreet binary from nixpkgs
          command = lib.concatStringsSep " " [
            "${pkgs.greetd.tuigreet}/bin/tuigreet"
            "--remember"
            "--width"
            "40"
            "--time"
            "--asterisks"
            "--theme"
            "'border=magenta;prompt=green;time=yellow;container=black;input=cyan'"
          ];
          user = "greeter"; # unprivileged greeter user
        };
      };
    };
  };

  security.pam.services = {
    greetd.enableGnomeKeyring = true;
    hyprlock.enableGnomeKeyring = true;
    enableGnomeKeyring = true;
  };

  networking = {
    useDHCP = false; # NM will do DHCP itself
    networkmanager = {
      enable = true;
      # wifi.backend = "iwd";      # make NM talk to iwd instead of wpa_supplicant
    };
  };

  fonts.packages = with pkgs; [
    nerd-fonts.hack
    nerd-fonts.ubuntu
  ];

  programs = {
    zsh.enable = true;
    hyprland = {
      enable = true;
      withUWSM = true;
      xwayland.enable = true;
    };
  };

  users.defaultUserShell = pkgs.zsh;

  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-macchiato.yaml";
    autoEnable = false;
    fonts.monospace = {
      name = "Hack Nerd Font";
      package = pkgs.nerd-fonts.hack;
    };
  };

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
    wl-clipboard

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
    obs-studio
  ];
}
