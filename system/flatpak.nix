{
  services.flatpak.enable = true;

  # Updates Flatpaks every time you run 'nixos-rebuild switch'
  services.flatpak.update.onActivation = true;

  # Automatically updates Flatpaks in the background via a systemd timer
  services.flatpak.update.auto = {
    enable = true;
    onCalendar = "daily"; # You can change this to "weekly" if you prefer
  };

  services.flatpak.remotes = [
    {
      name = "flathub";
      location = "https://flathub.org/repo/flathub.flatpakrepo";
    }
  ];
}
