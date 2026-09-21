{
  config,
  pkgs,
  ...
}: {
  # Single source of truth for GTK, X11/XWayland and Hyprland cursors.
  home.pointerCursor = {
    enable = true;
    name = "catppuccin-macchiato-dark-cursors";
    package = pkgs.catppuccin-cursors.macchiatoDark;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
    # Catppuccin provides both native Hyprcursor and fallback XCursor assets.
    hyprcursor.enable = true;
  };

  wayland.windowManager.hyprland.settings.config.cursor.enable_hyprcursor =
    config.home.pointerCursor.hyprcursor.enable;

  # Let XWayland applications scale themselves at 1.25x without compositor
  # scaling, which otherwise enlarges their cursors disproportionately.
  xresources.properties = {
    "Xft.dpi" = 120;
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
    font = {
      name = "Ubuntu Nerd Font";
      size = 11;
    };
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    # iconTheme = {
    #   name = "Adwaita";
    #   package = pkgs.adwaita-icon-theme;
    # };

    # Prefer a dark theme variant and show GTK 3 tooltips faster.
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
      gtk-tooltip-timeout = 80;
      gtk-tooltip-browse-timeout = 80;
      gtk-enable-animations = true;
    };
    gtk4.theme = config.gtk.theme;
  };
}
