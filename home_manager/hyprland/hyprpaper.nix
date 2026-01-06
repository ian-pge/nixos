# {
#   services.hyprpaper = {
#     enable = true;
#     settings = {
#       ipc = "off";
#       preload = ["${../../material/wallpaper.png}"];
#       wallpaper = [",${../../material/wallpaper.png}"]; # apply to all monitors
#     };
#   };
# }
{lib, ...}: let
  wp = "${../../material/wallpaper.png}";
in {
  services.hyprpaper.enable = true;

  # IMPORTANT: hyprpaper now uses `wallpaper { ... }` blocks
  # so we force-write the config file ourselves.
  xdg.configFile."hypr/hyprpaper.conf" = lib.mkForce {
    text = ''
      ipc = off
      splash = false

      wallpaper {
        monitor =
        path = ${wp}
        fit_mode = cover
      }
    '';
  };

  # Prevent the HM hyprpaper module from generating the old-style config keys
  services.hyprpaper.settings = lib.mkForce {};
}
