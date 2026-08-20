{inputs, ...}: {
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
    inputs.catppuccin.homeModules.catppuccin
    # inputs.hyprpanel.homeManagerModules.hyprpanel

    ./home_manager.nix
    ./chezmoi.nix
    ./git.nix
    ./direnv.nix
    ./additional_packages.nix
    ./desktop_packages.nix
    # ./mime_apps.nix
    ./gh.nix
    ./zed
    ./gtk.nix
    ./quickshell.nix
    ./tabctl.nix
    ./voxtype.nix
    ./hyprpaper.nix
    ./ghostty.nix
    ./catppuccin.nix
    ./hyprland
    ./fzf.nix
    # ./zsh.nix
    ./fish.nix
    # ./oh_my_posh.nix
    ./starship.nix
    ./waybar.nix
    # ./xdg_termfilechooser.nix
    ./fuzzel.nix
    ./mako.nix
    ./neovim.nix
    # ./hyprpanel.nix
    ./hypridle.nix
    ./hyprlock.nix
    ./mpv.nix
    ./cosmic.nix
    ./yazi.nix
    ./zathura.nix
  ];
}
