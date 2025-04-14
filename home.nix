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
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
    ];
    files = [ ".screenrc" ];
    allowOther = true;
  };

  # dconf settings for GNOME: configuring interface colors and theme.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };
  };

  # GTK settings: enable GTK, set dark theme and proper icon/cursor themes.
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.gnome.adwaita-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.gnome.adwaita-icon-theme;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
  };
}
