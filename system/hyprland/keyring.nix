{
  services.gnome.gnome-keyring.enable = true;

  security.pam.services = {
    greetd.enableGnomeKeyring = true;
    hyprlock.enableGnomeKeyring = true;
    gnome.enableGnomeKeyring = true;
    login.enableGnomeKeyring = true;
  };
}
