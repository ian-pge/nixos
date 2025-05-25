{
  # Enable dconf to manage GNOME settings
  # dconf.settings = {
  #   "org/gnome/desktop/interface" = {
  #     color-scheme = "prefer-dark"; # Preferred color scheme
  #     gtk-theme = "Adwaita-dark"; # Set GTK theme to Adwaita-dark
  #   };
  # };

  # Configure GTK settings
  gtk = {
    enable = true;
    # theme = {
    #   name = "Adwaita-dark";
    #   package = pkgs.gnome-themes-extra;
    # };
    # iconTheme = {
    #   name = "Adwaita";
    #   package = pkgs.adwaita-icon-theme;
    # };
    # cursorTheme = {
    #   name = "catppuccin-macchiato-dark-cursors";
    #   package = pkgs.catppuccin-cursors.macchiatoDark;
    # };

    # # Tells GTK 3 to prefer a dark theme variant
    # gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
  };
}
