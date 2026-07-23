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
      font-family = "JetBrainsMono Nerd Font";
      font-size = "12";
      keybind = [
        "ctrl+y=scroll_page_lines:-1"
        "ctrl+e=scroll_page_lines:1"
        "ctrl+u=scroll_page_up"
        "ctrl+d=scroll_page_down"
      ];
    };
  };
}
