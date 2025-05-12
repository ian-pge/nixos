{pkgs, ...}: {
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting

      functions -q prompt_newline; and prompt_newline >/dev/null

      fish_vi_key_bindings
      bind yy fish_clipboard_copy
      bind -M visual y fish_clipboard_copy
      bind -M default p forward-char-passive fish_clipboard_paste backward-char-passive
      bind -M default P fish_clipboard_paste
    '';
    plugins = [
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];
  };
}
