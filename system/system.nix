{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    (import ./disko.nix {device = "/dev/nvme0n1";})

    inputs.disko.nixosModules.default
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.default

    ./hardware-configuration.nix
    ./config/boot.nix
    ./config/persistance.nix
    ./config/nixos_config.nix
  ];

  hardware = {
    keyboard.qmk.enable = true;
    nvidia-container-toolkit.enable = true;
  };

  programs = {
    fuse.userAllowOther = true;
    dconf.enable = true;
    nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/etc/nixos";
    };
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
    };
  };

  services = {
    openssh.enable = true;
    udev = {
      packages = [
        pkgs.via
      ];
      extraRules = ''
        ${builtins.readFile ../material/99-slabs.rules}
      '';
    };
  };

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";
  };

  environment.systemPackages = with pkgs; [
    zed-editor
    devpod
    bambu-studio
    google-chrome
    blender
    davinci-resolve
    nvd
    nix-output-monitor
    via
    zotero
  ];
}
