{
  programs.neovim = {
    enable = true;
    programs.neovim.extraLuaConfig = ''
      require('lspconfig').nixd.setup {
        cmd = { "nixd" },
        filetypes = { "nix" },
        root_dir = require('lspconfig').util.root_pattern("flake.nix", "shell.nix", ".git"),
        settings = {
          nixd = {
            nixpkgs = {
              expr = "import <nixpkgs> { }",
            },
          },
        },
      }
    '';
  };
}
