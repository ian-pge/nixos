{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ../shared
    ./gtk.nix
    ./additional_packages.nix
    ./hyprpaper.nix
    ./ghostty.nix
    ./stylix.nix
    ./hyprland.nix
    ./fzf.nix
    ./zsh.nix
    ./oh_my_posh.nix
    ./waybar.nix
  ];

  home.sessionVariables.GTK_USE_PORTAL = "1";

  xdg.portal = {
    enable = lib.mkForce true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-termfilechooser
    ];
    config.common = {
      default = ["termfilechooser" "hyprland"];
      "org.freedesktop.impl.portal.FileChooser" = ["termfilechooser"];
    };
  };
  # ---- make the portal launch Ghostty ----
  # environment.variables.TERMCMD = "${pkgs.ghostty}/bin/ghostty --app-id file_chooser";

  # ---- ship the wrapper & config declaratively ----
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=${pkgs.xdg-desktop-portal-termfilechooser}/share/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh
    default_dir=$HOME
    env=TERMCMD=ghostty -e
    open_mode=suggested
    save_mode=last
  '';
}
