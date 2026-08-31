{
  lib,
  pkgs,
  ...
}: let
  userSession = pkgs.writeShellApplication {
    name = "greetd-uwsm-session";
    text = ''
      exec ${lib.getExe pkgs.uwsm} start -e -D Hyprland -- \
        hyprland.desktop -- --locked-cmd "${lib.getExe pkgs.hyprlock} --config /home/ian/.config/hypr/hyprlock-boot.conf --immediate-render"
    '';
  };
in {
  services.greetd = {
    enable = true;
    settings = {
      # Use the same fail-closed path at boot and after every logout: greetd
      # starts a fresh desktop whose first visible client is Hyprlock.
      default_session = {
        command = lib.getExe userSession;
        user = "ian";
      };
    };
  };
}
