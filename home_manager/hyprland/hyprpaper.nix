{
  services.hyprpaper = {
    enable = true; # turn on the hyprpaper service
    settings = {
      ipc = "off"; # enable fast IPC mode for live changes
      preload = ../../material/wallpaper.png; # images to load at startup
      wallpaper = ../../material/wallpaper.png; # apply to all monitors
    };
  };
}
