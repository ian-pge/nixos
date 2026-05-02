{
  users.users."ian".extraGroups = ["docker"];

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation.docker = {
    enable = true;
    daemon.settings.features.cdi = true;
    storageDriver = "btrfs";
  };
}
