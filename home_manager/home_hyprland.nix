{ pkgs, ... }:

{
  imports = [
    ./home.nix
  ];

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

  programs.kitty.enable = true;

  wayland.windowManager.hyprland = {
    enable = true;
    # Additional Hyprland configurations can go here
  };
}
