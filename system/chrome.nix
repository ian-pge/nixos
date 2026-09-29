{
  programs.google-chrome = {
    enable = true;
    extensions = [
      "gfbliohnnapiefjpjlpjnehglfpaknnc" # Surfingkeys
      "gighmmpiobklfepjocnamgkkbiglidom" # AdBlock
      # Catppuccin's Chrome theme, macchiato flavor (same ID as catppuccin/nix,
      # whose module only targets Chromium, Brave, and Vivaldi).
      "cmpdlhmnmjhihmcfnigoememnffkimlk" # Catppuccin Macchiato
    ];
  };
}
