{ inputs, ... }:

{
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
  ];

  # Set the home-manager state version (do not change unless you know why).
  home.stateVersion = "24.11";

  # Home persistence configuration: list all directories and files you want to persist.
  home.persistence."/persist/home/ian" = {
    directories = [
      "Downloads"
      "Music"
      "Pictures"
      "Documents"
      "Videos"
      "PhD"
      "Perso"
      ".ssh"
      ".config/zed"
      {
        directory = ".local/share/zed";
        method = "symlink";
      }

      # Gnome
      ".config/dconf"
      ".local/share/keyrings"
      ".devpod"

      ".config/google-chrome"

      {
        directory = ".local/share/Steam";
        method = "symlink";
      }

    ];
    files = [
      ".config/monitors.xml"
      ".config/history/.backup"
    ];
    allowOther = true;
  };

  programs.git = {
    enable = true;
    userName  = "ian";
    userEmail = "ian.page38@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      safe.directory = "/etc/nixos";
    };
  };
}
