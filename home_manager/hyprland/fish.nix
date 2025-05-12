{pkgs, ...}: {
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting

      functions -q prompt_newline; and prompt_newline >/dev/null

      function __vim_put_after_clipboard \
              --description 'Vim-style p: paste clipboard AFTER the cursor'
          commandline -f forward-char           # move one cell right
          fish_clipboard_paste                  # insert clipboard contents
          commandline -f backward-char          # land cursor before the pasted text
      end

      fish_vi_key_bindings
      bind yy fish_clipboard_copy
      bind -M visual y fish_clipboard_copy
      bind -M default P fish_clipboard_paste
      bind -M default p '__vim_put_after_clipboard'
    '';
    plugins = [
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];
  };
}
