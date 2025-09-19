{
  programs.dconf.enable = true;

  services = {
    desktopManager.gnome.enable = true;
    displayManager.gdm.enable = true;
    xserver = {
      enable = true;
      videoDrivers = ["nvidia"];
    };
  };
}
