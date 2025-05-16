{
  services.hyprpaper = {
    enable = true;
    settings = {
      ipc = "off";
      preload = ["${../../material/wallpaper.png}"];
      wallpaper = [",${../../material/wallpaper.png}"]; # apply to all monitors
    };
  };
}
