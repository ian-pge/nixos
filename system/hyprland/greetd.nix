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
          "'border=magenta;prompt=yellow;time=cyan;container=black;input=green'"
        ];
        user = "greeter"; # unprivileged greeter user
      };
    };
  };
}
