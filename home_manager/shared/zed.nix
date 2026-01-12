{
  programs.zed-editor = {
    enable = true;

    # This whole block is rendered to ~/.config/zed/settings.json
    userSettings = {
      assistant = {
        default_model = {
          provider = "anthropic";
          model = "claude-3-7-sonnet-latest";
        };
        version = "2";
      };

      inlay_hints = {
        enabled = true;
      };

      # Added session settings here
      session = {
        trust_all_worktrees = true;
      };

      icon_theme = "Catppuccin Macchiato";
      features = {
        edit_prediction_provider = "zed";
      };
      restore_on_startup = "none";

      tab_size = 2;

      lsp = {
        nil = {
          binary = {path_lookup = true;};
          initialization_options = {
            formatting = {
              command = ["alejandra"];
            };
          };
        };
        texpresso-lsp = {
          initialization_options = {
            root_tex = "main.tex";
          };
        };
        # texlab = {
        #   settings = {
        #     texlab = {
        #       build = {
        #         onSave = true;
        #       };
        #     };
        #   };
        # };
      };

      languages = {
        Nix = {
          format_on_save = "on";
          formatter = "language_server";
        };
      };

      show_edit_predictions = true;
      vim_mode = true;
      vim = {
        cursor_shape = {
          normal = "block";
          insert = "bar";
          replace = "underline";
          visual = "block";
        };
      };

      # theme = {
      #   mode = "system";
      #   dark = "Catppuccin Macchiato (sapphire)";
      # };

      terminal = {
        font_family = "Hack Nerd Font";
        dock = "bottom";
        font_size = 16;
        blinking = "on";
        line_height = "standard";
      };

      buffer_font_family = "Hack Nerd Font";
      buffer_font_size = 16;

      ui_font_family = "Ubuntu Nerd Font";
      ui_font_size = 16;
    };
  };
}
