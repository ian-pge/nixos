{pkgs, ...}: {
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

  # ---- ship the wrapper & config declaratively ----
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=${pkgs.xdg-desktop-portal-termfilechooser}/share/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh
    default_dir=$HOME
    env=TERMCMD=ghostty --app-id=file_chooser -e
    open_mode=suggested
    save_mode=last
  '';
}
