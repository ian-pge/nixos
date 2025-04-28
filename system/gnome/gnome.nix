{
  programs.dconf.enable = true;

  services.xserver = {
    enable = true;
    videoDrivers = ["nvidia"];
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };
}
