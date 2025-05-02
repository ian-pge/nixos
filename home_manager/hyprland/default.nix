{inputs, ...}: {
  imports = [
    inputs.catppuccin.homeModules.catppuccin

    ../shared
    ./gtk.nix
    ./additional_packages.nix
    ./hyprpaper.nix
    ./ghostty.nix
    # ./stylix.nix
    ./hyprland.nix
    ./fzf.nix
    # ./zsh.nix
    ./fish.nix
    # ./oh_my_posh.nix
    ./starship.nix
    ./waybar.nix
    ./xdg_termfilechooser.nix
    ./fuzzel.nix
    ./mako.nix
  ];
}
