{
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    keymap.mgr.prepend_keymap = [
      {
        on = ["<Enter>"];
        run = ["open" "quit"];
        desc = "Open selected file then quit";
      }
    ];
  };
}
