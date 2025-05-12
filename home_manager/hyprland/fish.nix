{pkgs, ...}: {
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting

      functions -q prompt_newline; and prompt_newline >/dev/null

      fish_vi_key_bindings
      bind yy fish_clipboard_copy
      bind -M visual y fish_clipboard_copy
      bind -M default p fish_clipboard_paste
    '';
    plugins = [
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];
  };
}
