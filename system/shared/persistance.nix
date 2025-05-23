{
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist/system" = {
    hideMounts = true;
    directories = [
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

  environment.persistence."/persist" = {
    hideMounts = true;
    users.ian = {
      directories = [
        "Music"
        "Documents"
        "Videos"
        "PhD"
        "Perso"
        "Pictures"
        "Downloads"

        ".config/nixos"

        ".local/share/zed"
        ".config/zed"
        ".ssh"
        ".devpod"
        ".config/google-chrome"
        ".local/share/applications"
        ".local/share/icons"
        ".config/BambuStudio"
        ".local/share/lutris"
        ".config/Code"
        ".vscode"
        ".config/obs-studio"
        ".local/share/oculante"
        ".config/nautilus"
        ".local/share/nautilus"
        ".config/history"
        ".zotero"
        ".config/dconf"
        ".cache"
        ".local/share/keyrings"
      ];
      files = [
        ".config/monitors.xml"
        ".config/mimeapps.list"
      ];
    };
  };

  programs.fuse.userAllowOther = true;

  # systemd.tmpfiles.rules = [
  #   "d /persist/home 0777 root root -"
  #   "d /persist/home/ian 0700 ian users -"
  # ];
}
