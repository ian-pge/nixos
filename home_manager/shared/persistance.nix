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
      ".config/zed"
      {
        directory = ".local/share/zed";
        method = "symlink";
      }
      ".config/history"
      ".zotero"
      # Gnome
      ".config/dconf"
      ".local/share/keyrings"
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
    ];
    files = [
      ".config/monitors.xml"
    ];
    allowOther = true;
  };
}
