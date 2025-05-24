{pkgs, ...}: {
  # put COSMIC Files in front of every other file-manager service
  # xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
  #   [D-BUS Service]
  #   Name=org.freedesktop.FileManager1
  #   Exec=${pkgs.cosmic-files}/bin/cosmic-files %u
  # '';

  # xdg.portal = {
  #   enable = true;
  #   # pull in the Hyprland-aware backend
  #   extraPortals = [pkgs.xdg-desktop-portal-cosmic];
  #   # make it the default so GNOME’s backend is ignored
  #   config.common = {
  #     "org.freedesktop.impl.portal.FileChooser" = ["cosmic"];
  #   };
  # };

  # home.packages = with pkgs; [
  #   cosmic-files
  #   cosmic-ext-calculator
  #   cosmic-settings
  #   cosmic-osd
  #   cosmic-player
  #   catppuccin-papirus-folders
  # ];

  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications."inode/directory" = "cosmic-files.desktop";
}
