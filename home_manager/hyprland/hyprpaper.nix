{
  services.hyprpaper = {
    enable = true;
    settings = let
      wp = ../../material/wallpaper.png; # relative to this .nix file
    in {
      ipc = "off";
      preload = ["${wp}"];
      wallpaper = [",${wp}"]; # apply to all monitors
    };
  };
}
