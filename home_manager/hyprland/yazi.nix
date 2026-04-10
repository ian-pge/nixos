{
  programs.yazi = {
    enable = true;
    shellWrapperName = "yy";
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
