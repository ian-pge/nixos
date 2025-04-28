{
  lib,
  pkgs,
  ...
}: {
  services.greetd = {
    enable = true; # start greetd daemon
    vt = 1; # run on tty1
    settings = {
      default_session = {
        # tuigreet binary from nixpkgs
        command = lib.concatStringsSep " " [
          "${pkgs.greetd.tuigreet}/bin/tuigreet"
          "--remember"
          "--width"
          "40"
          "--time"
          "--asterisks"
          "--theme"
          "'border=magenta;prompt=green;time=yellow;container=black;input=cyan'"
        ];
        user = "greeter"; # unprivileged greeter user
      };
    };
  };

  xdg.portal = {
    enable = true;
    # Hyprland’s compositor portal for screenshots, etc.
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk # keep gtk for colour picker etc.
      pkgs.xdg-desktop-portal-termfilechooser
    ];

    # Make termfilechooser the FileChooser backend
    config = {
      Hyprland = {
        default = ["hyprland" "gtk"]; # fallback order
        "org.freedesktop.impl.portal.FileChooser" = ["termfilechooser"];
      };
    };
  };
}
