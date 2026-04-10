{
  programs.neovim = {
    enable = true;
    withRuby = true;
    withPython3 = true;
    initLua = ''
      vim.opt.number = true
      vim.opt.shortmess:append("I")
    '';
  };
}
