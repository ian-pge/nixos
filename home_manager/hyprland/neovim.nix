{
  programs.neovim = {
    enable = true;
    extraLuaConfig = ''
      vim.opt.number = true
    '';
  };
}
