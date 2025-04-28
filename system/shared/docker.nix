{
  users.users."ian".extraGroups = ["docker"];

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";
  };
}
