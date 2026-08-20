{pkgs, ...}: {
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    flags = [
      "--disable-up-arrow"
      "--disable-ai"
    ];
  };

  programs.fish = {
    enable = true;

    functions = {
      starship_transient_prompt_func.body = ''starship module time'';
      fish_title.body = ''
        # Disable Fish's default prompt/path terminal title updates so OSC2
        # titles set by Zed tasks or scripts remain visible.
        true
      '';
      fish_tab_title.body = ''
        # Fish 4 can set a separate tab title. Keep it quiet too.
        true
      '';
      zed_title.body = ''
        # Set Zed's terminal-title breadcrumb (not the Zed tab label).
        set -l title (string join " " -- $argv)
        printf '\033]2;%s\007' "$title"
      '';
      prompt_newline = {
        onEvent = "fish_postexec";
        body = ''echo'';
      };
    };

    interactiveShellInit = ''
      set fish_greeting

      functions -q prompt_newline; and prompt_newline >/dev/null

      # Fish owns command-line Vi editing in every terminal, including Zed.
      # Zed's native terminal Vi mode only navigates terminal scrollback and
      # cannot replace Fish's normal/insert modes.
      fish_vi_key_bindings

      bind yy fish_clipboard_copy
      bind -M visual y fish_clipboard_copy
      # bind -M default p forward-char-passive fish_clipboard_paste backward-char-passive
      # bind -M default P fish_clipboard_paste

    '';
    plugins = [
      {
        name = "bass";
        src = pkgs.fishPlugins.bass.src;
      }
    ];
  };
}
