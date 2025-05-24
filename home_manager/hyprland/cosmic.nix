{pkgs, ...}: {
  # put COSMIC Files in front of every other file-manager service
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${pkgs.cosmic-files}/bin/cosmic-files %u
  '';

  home.packages = with pkgs; [
    cosmic-files
    cosmic-ext-calculator
    cosmic-settings
    cosmic-osd
    cosmic-player
    xdg-desktop-portal-cosmic
    catppuccin-papirus-folders
  ];
}
