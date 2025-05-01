{
  users.users."ian".extraGroups = ["docker"];

  hardware.nvidia-container-toolkit.enable = true;
  hardware.nvidia-container-toolkit.mount-nvidia-docker-1-directories = true;
  hardware.nvidia-container-toolkit.mount-nvidia-executables = true;

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";
  };
}
