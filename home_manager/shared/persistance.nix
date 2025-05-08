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

      ".ssh"
      ".devpod"
      ".config/google-chrome"
      ".local/share/applications"
      ".local/share/icons"
      # ".config/zed"
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
      ".local/share/Steam"
      # ".steam"
      # {
      #   directory = ".local/share/Steam";
      #   method = "symlink";
      # }
    ];
    files = [
      ".config/monitors.xml"
    ];
    allowOther = true;
  };
}
