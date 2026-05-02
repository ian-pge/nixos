{
  programs.zed-editor = {
    enable = true;
    mutableUserSettings = false;

    # This whole block is rendered to ~/.config/zed/settings.json
    userSettings = {
      disable_ai = true;

      file_scan_exclusions = [
        "**/.git"
        "**/node_modules"
        "**/.local/share/mise"
        "**/.local/share/pnpm"
        "**/.cache"
        "**/.npm"
        "**/.cargo"
        "**/.rustup"
        "**/target"
        "**/dist"
        "**/.next"
        "**/__pycache__"
        "**/.venv"
      ];

      agent = {
        enabled = false;
        button = false;
      };

      inlay_hints = {
        enabled = true;
      };

      # Added session settings here
      session = {
        trust_all_worktrees = true;
      };

      icon_theme = "Catppuccin Macchiato";
      edit_predictions = {
        provider = "zed";
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

      project_panel = {
        dock = "left";
      };

      git_panel = {
        dock = "left";
      };

      outline_panel = {
        dock = "left";
      };

      collaboration_panel = {
        dock = "right";
        button = false;
      };


      terminal = {
        font_family = "Hack Nerd Font";
        dock = "right";
        font_size = 16;
        blinking = "on";
        line_height = "standard";
      };

      active_pane_modifiers = {
        border_size = 2.0;
        inactive_opacity = 1.0;
      };

      buffer_font_family = "Hack Nerd Font";
      buffer_font_size = 16;

      ui_font_family = "Ubuntu Nerd Font";
      ui_font_size = 16;
    };
    userKeymaps = [
      {
        context = "Pane";
        bindings = {
          "alt-h" = "pane::SplitLeft";
          "alt-j" = "pane::SplitDown";
          "alt-k" = "pane::SplitUp";
          "alt-l" = "pane::SplitRight";
          "ctrl-w" = "pane::CloseActiveItem";
        };
      }
      {
        context = "VimControl";
        bindings = {
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-j" = "workspace::ActivatePaneDown";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-l" = "workspace::ActivatePaneRight";
        };
      }
      {
        context = "Dock";
        bindings = {
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-j" = "workspace::ActivatePaneDown";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-l" = "workspace::ActivatePaneRight";
        };
      }
      {
        context = "Terminal";
        bindings = {
          "ctrl-y" = "terminal::ScrollLineUp";
          "ctrl-e" = "terminal::ScrollLineDown";
          "ctrl-u" = "terminal::ScrollPageUp";
          "ctrl-d" = "terminal::ScrollPageDown";
          "alt-h" = "pane::SplitLeft";
          "alt-j" = "pane::SplitDown";
          "alt-k" = "pane::SplitUp";
          "alt-l" = "pane::SplitRight";
          "ctrl-w" = "pane::CloseActiveItem";
        };
      }
      # {
      #   # Forcefully target both code editors AND terminal tabs
      #   context = "Editor || VimControl || Terminal";
      #   bindings = {
      #     "ctrl-alt-h" = "vim::ResizePaneLeft";
      #     "ctrl-alt-j" = "vim::ResizePaneDown";
      #     "ctrl-alt-k" = "vim::ResizePaneUp";
      #     "ctrl-alt-l" = "vim::ResizePaneRight";
      #   };
      # }
    ];
  };
}
