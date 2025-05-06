{
  pkgs,
  lib,
  ...
}: {
  programs.helix = {
    enable = true;

    ### Core editor settings -----------------------------------------------
    settings = {
      editor = {
        "color-modes" = true; # colour the mode indicator :contentReference[oaicite:0]{index=0}

        "cursor-shape" = {
          # mode-specific cursor :contentReference[oaicite:1]{index=1}
          normal = "block";
          insert = "bar";
          select = "underline";
        };
      };

      # pull in Vim-style key bindings
      import = [
        "./config.toml" # helix-vim default map :contentReference[oaicite:2]{index=2}
      ];
    };

    ### Language servers (optional but nice) -------------------------------
    # languages = lib.mkIf pkgs.stdenv.isLinux {
    #   # adjust per-OS if needed :contentReference[oaicite:3]{index=3}
    #   language = [
    #     {
    #       name = "bash";
    #       language-server.command = "${pkgs.bashLanguageServer}/bin/bash-language-server";
    #     }
    #     {
    #       name = "fish";
    #       language-server.command = "${pkgs.fish}/bin/fish";
    #     }
    #     {
    #       name = "nix";
    #       language-server.command = "${pkgs.nixd}/bin/nixd";
    #     }
    #     {
    #       name = "python";
    #       language-server.command = "${pkgs.pyright}/bin/pyright-langserver";
    #       language-server.args = ["--stdio"];
    #     }
    #     {
    #       name = "json";
    #       language-server.command = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
    #       language-server.args = ["--stdio"];
    #     }
    #     {
    #       name = "c";
    #       language-server.command = "${pkgs.clang-tools}/bin/clangd";
    #     }
    #     {
    #       name = "cpp";
    #       language-server.command = "${pkgs.clang-tools}/bin/clangd";
    #     }
    #   ];
    # };

    ### Extra binary (optional) -------------------------------------------
    # package = pkgs.helix;  # uncomment to override with a pinned helix if desired :contentReference[oaicite:5]{index=5}
  };
}
