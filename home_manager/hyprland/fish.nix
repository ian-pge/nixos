{pkgs, ...}: {
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting

      functions -q prompt_newline; and prompt_newline >/dev/null

      fish_vi_key_bindings
      bind yy fish_clipboard_copy
      bind -M visual y fish_clipboard_copy
      # bind -M default p forward-char-passive fish_clipboard_paste backward-char-passive
      # bind -M default P fish_clipboard_paste

      function _aichat_fish
          set -l text (commandline)
          if test -n "$text"
              commandline -r ""                     # clear your input
              printf '\r\e[2C\e[K'                 # show icon at col 3, clear rest of line
              set -l out (aichat -e -- "$text")     # run AI
              commandline -r "$out"                 # replace with AI output
              commandline -f repaint                 # redraw prompt (overwrites the icon)
          end
      end
      bind \ee _aichat_fish

    '';
    plugins = [
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];
  };
}
