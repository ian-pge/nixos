{
  home.stateVersion = "25.05";

  nix.extraOptions = ''
    !include /home/ian/.config/nix/access-tokens
  '';
}
