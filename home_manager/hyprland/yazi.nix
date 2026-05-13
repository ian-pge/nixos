{
  programs.yazi = {
    enable = true;
    shellWrapperName = "yy";
    enableFishIntegration = true;
    settings = {
      opener.zed = [
        {
          run = "zeditor -n %s";
          desc = "Open in Zed (new window)";
          orphan = true;
          for = "unix";
        }
      ];
      open.prepend_rules = [
        {
          url = "*/";
          use = "zed";
        }
      ];
    };
    keymap.mgr.prepend_keymap = [
      {
        on = ["<Enter>"];
        run = ["open" "quit"];
        desc = "Open selected file then quit";
      }
    ];
  };
}
