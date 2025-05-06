{
  programs.neovim = {
    enable = true;
    extraLuaConfig = ''
      vim.opt.number = true
      vim.opt.shortmess:append("I")
    '';
  };
}
