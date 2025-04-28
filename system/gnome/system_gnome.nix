{
  config,
  inputs,
  ...
}: {
  home-manager = {
    useGlobalPkgs = true;
    extraSpecialArgs = {inherit inputs;};
    backupFileExtension = "backup";
    users = {
      "ian" = import ../../home_manager/home_gnome.nix;
    };
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  programs.dconf.enable = true;

  services = {
    xserver = {
      enable = true;
      videoDrivers = ["nvidia"];
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
    };
  };
}
