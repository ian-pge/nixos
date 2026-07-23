{
  pkgs,
  config,
  lib,
  ...
}: let
  desktopFile = "paper-desktop.desktop";
in {
  home.packages = [pkgs.paper-desktop];

  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "x-scheme-handler/paper" = desktopFile;
      "x-scheme-handler/paper-dev" = desktopFile;
    };
    defaultApplications = {
      "x-scheme-handler/paper" = desktopFile;
      "x-scheme-handler/paper-dev" = desktopFile;
    };
  };

  # Keep a user-local desktop entry so xdg-desktop-portal / GNOME's app
  # chooser can discover the custom Paper URL scheme reliably on Hyprland.
  xdg.dataFile."applications/${desktopFile}".text = ''
    [Desktop Entry]
    Name=Paper
    Exec=${pkgs.paper-desktop}/bin/paper-desktop --no-sandbox %U
    Terminal=false
    Type=Application
    Icon=paper-desktop
    StartupWMClass=Paper
    Comment=Paper Desktop
    MimeType=x-scheme-handler/paper;x-scheme-handler/paper-dev;
    Categories=Utility;
  '';

  home.activation.updatePaperDesktopDatabase = lib.hm.dag.entryAfter ["writeBoundary"] ''
    $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database ${lib.escapeShellArg config.xdg.dataHome}/applications
  '';
}
