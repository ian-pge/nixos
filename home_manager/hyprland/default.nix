{inputs, ...}: {
  imports = [
    inputs.catppuccin.homeModules.catppuccin
    # inputs.hyprpanel.homeManagerModules.hyprpanel

    ../shared
    ./gtk.nix
    ./additional_packages.nix
    ./hyprpaper.nix
    ./ghostty.nix
    ./catppuccin.nix
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
    ./neovim.nix
    # ./hyprpanel.nix
  ];
}
