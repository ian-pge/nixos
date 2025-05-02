{
  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      cursor-style-blink = true;
      cursor-style = "block";
      window-padding-x = 7;
      window-padding-y = 7;
      # shell-integration-features = "no-cursor";
      confirm-close-surface = false;
      resize-overlay = "never";
      adjust-cursor-thickness = "200%";
      font = "Hack Nerd Font 16";
    };
  };
}
