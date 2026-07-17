{
  config,
  pkgs,
  ...
}: {
  # Let XWayland applications scale themselves at 1.25x without compositor
  # scaling, which otherwise enlarges their cursors disproportionately.
  xresources.properties = {
    "Xft.dpi" = 120;
    "Xcursor.size" = 24;
  };

  # Enable dconf to manage GNOME settings
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark"; # Preferred color scheme
      # gtk-theme = "Adwaita-dark"; # Set GTK theme to Adwaita-dark
    };
  };

  # Configure GTK settings
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    # iconTheme = {
    #   name = "Adwaita";
    #   package = pkgs.adwaita-icon-theme;
    # };
    cursorTheme = {
      name = "catppuccin-macchiato-dark-cursors";
      package = pkgs.catppuccin-cursors.macchiatoDark;
    };

    # Tells GTK 3 to prefer a dark theme variant and makes GTK tooltips
    # appear faster. Waybar is GTK3, so this affects its tooltips too.
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-tooltip-timeout = 80;
      gtk-tooltip-browse-timeout = 80;
      gtk-enable-animations = true;
    };
    gtk4.theme = config.gtk.theme;
  };
}
