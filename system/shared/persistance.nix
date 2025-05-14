{
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist/system" = {
    hideMounts = true;
    directories = [
      "/etc/nixos"
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/docker"
      "/var/lib/libvirt"
      "/var/lib/tailscale"
      "/var/lib/NetworkManager"
      "/var/cache/tuigreet"
      "/etc/NetworkManager/system-connections"
      {
        directory = "/var/lib/colord";
        user = "colord";
        group = "colord";
        mode = "u=rwx,g=rx,o=";
      }
    ];
    files = [
      "/etc/machine-id"
      {
        file = "/var/keys/secret_file";
        parentDirectory = {mode = "u=rwx,g=,o=";};
      }
    ];
  };

  programs.fuse.userAllowOther = true;

  systemd.tmpfiles.rules = [
    "d /persist/home 0777 root root -"
    "d /persist/home/ian 0700 ian users -"
  ];
}
