{
  home.persistence."/persist/home/ian" = {
    directories = [
      "Downloads"
      "Music"
      "Pictures"
      "Documents"
      "Videos"
      "PhD"
      "Perso"

      ".config/nixos"
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
      {
        directory = ".local/share/zed";
        method = "symlink";
      }
      {
        directory = ".config/zed";
        method = "symlink";
      }
      ".config/history"
      ".zotero"
      # Gnome
      ".config/dconf"
      ".cache"
      ".local/share/keyrings"
      # ".local/share/Steam"
      # ".steam"
    ];
    files = [
      ".config/monitors.xml"
      ".config/mimeapps.list"
    ];
    allowOther = true;
  };
}
