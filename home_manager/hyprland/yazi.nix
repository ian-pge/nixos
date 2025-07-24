{
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    keymap = {
      manager.prepend_keymap = [
        {
          on = ["enter"];
          run = ["open" "quit"];
          desc = "Open selected file then quit";
        }
      ];
    };
  };
}
