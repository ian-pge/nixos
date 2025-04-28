{
  services.hyprpaper = {
    enable = true; # turn on the hyprpaper service
    settings = {
      ipc = "off"; # enable fast IPC mode for live changes
      preload = ["/etc/nixos/material/wallpaper.png"]; # images to load at startup
      wallpaper = [",/etc/nixos/material/wallpaper.png"]; # apply to all monitors
    };
  };
}
