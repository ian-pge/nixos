{pkgs, ...}: {
  programs.zsh = {
    sessionVariables = {
      LANG = "en_US.UTF-8";
      ZSH_SYSTEM_CLIPBOARD_METHOD = "wlc";
      ZSH_SYSTEM_CLIPBOARD_USE_WL_CLIPBOARD = "true";
    };
    enable = true;
    enableCompletion = true;
    plugins = [
      {
        name = "zsh-system-clipboard";
        src = pkgs.zsh-system-clipboard;
        file = "share/zsh/zsh-system-clipboard/zsh-system-clipboard.zsh";
      }
      {
        name = "fast-syntax-highlighting";
        src = pkgs.zsh-fast-syntax-highlighting;
        file = "share/zsh/site-functions/fast-syntax-highlighting.plugin.zsh";
      }
      {
        name = "zsh-autosuggestions";
        src = pkgs.zsh-autosuggestions;
        file = "share/zsh-autosuggestions/zsh-autosuggestions.zsh";
      }
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
    ];
    initContent = ''
      bindkey -v
    '';
  };
}
