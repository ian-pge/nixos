{pkgs, ...}: {
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting

      functions -q prompt_newline; and prompt_newline >/dev/null

      function __vim_put_after_clipboard
        commandline -f forward-char
        fish_clipboard_paste
        commandline -f backward-char
      end

      fish_vi_key_bindings
      bind yy fish_clipboard_copy
      bind -M visual y fish_clipboard_copy
      # bind -M default P fish_clipboard_paste
      bind -M default p __vim_put_after_clipboard
    '';
    plugins = [
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];
  };
}
