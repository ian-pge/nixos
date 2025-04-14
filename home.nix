{ pkgs, inputs, ... }:

{
  # Import impermanence integration for home-manager.
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
  ];

  # Set the home-manager state version (do not change unless you know why).
  home.stateVersion = "24.11";

  # Home persistence configuration: list all directories and files you want to persist.
  home.persistence."/persist/home" = {
    directories = [
      "Downloads"
      "Music"
      "Pictures"
      "Documents"
      "Videos"
      "VirtualBox VMs"
      ".gnupg"
      ".ssh"
      ".nixops"
      ".local/share/keyrings"
      ".local/share/direnv"
      ".config/google-chrome"
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
    ];
    files = [ ".screenrc" ];
    allowOther = true;
  };

  # Enable dconf to manage GNOME settings
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";  # Preferred color scheme
      gtk-theme = "Adwaita-dark";    # Set GTK theme to Adwaita-dark
    };
  };

  # Configure GTK settings
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };

    # Tells GTK 3 to prefer a dark theme variant
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
  };
}
