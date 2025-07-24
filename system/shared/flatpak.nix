{
  services.flatpak.enable = true;
  services.flatpak.update.onActivation = true;
  services.flatpak.remotes = [
    {
      name = "flathub";
      location = "https://flathub.org/repo/flathub.flatpakrepo";
    }
  ];
}
