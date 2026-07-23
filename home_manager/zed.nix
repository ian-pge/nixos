{
  programs.zed-editor = {
    enable = true;
    mutableUserSettings = false;

    # This whole block is rendered to ~/.config/zed/settings.json
    userSettings = {
      disable_ai = true;
      dev_container_suggest_dismissed = true;
      cli_default_open_behavior = "new_window";

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
        font_family = "JetBrainsMono Nerd Font";
        dock = "right";
        font_size = 16;
        blinking = "on";
        line_height = "standard";
        toolbar = {
          breadcrumbs = true;
        };
      };

      # Zed draws this active pane border with the global theme token
      # "border.selected". The terminal panel is implemented as the same kind of
      # pane group as editor panes, so Zed currently cannot color only terminal
      # panes differently from code panes through settings.json.
      active_pane_modifiers = {
        border_size = 2.0;
        inactive_opacity = 1.0;
      };

      buffer_font_family = "JetBrainsMono Nerd Font";
      buffer_font_size = 16;

      ui_font_family = "Ubuntu Nerd Font";
      ui_font_size = 16;
    };
    userKeymaps = [
      {
        # Global workspace shortcuts: Ctrl+Space toggles pane zoom,
        # Ctrl+Enter opens a terminal tab, and Ctrl+T shows/hides the terminal.
        bindings = {
          "ctrl-space" = "workspace::ToggleZoom";
          "ctrl-enter" = "workspace::NewTerminal";
          "ctrl-t" = "terminal_panel::Toggle";
          "shift-escape" = null;
        };
      }
      {
        context = "Pane";
        bindings = {
          "alt-h" = "pane::SplitLeft";
          "alt-j" = "pane::SplitDown";
          "alt-k" = "pane::SplitUp";
          "alt-l" = "pane::SplitRight";
          # Keep pane navigation available when a terminal or other non-editor
          # item is zoomed/full-screened into the center pane.
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-j" = "workspace::ActivatePaneDown";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-l" = "workspace::ActivatePaneRight";
          "ctrl-w" = "pane::CloseActiveItem";
        };
      }
      {
        context = "VimControl && !menu";
        bindings = {
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-j" = "workspace::ActivatePaneDown";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-l" = "workspace::ActivatePaneRight";

          # Vim-style leader bindings for Zed's fuzzy finders.
          # <space><space> / <space>ff: find files by name.
          # <space>/ / <space>sg: find text across the project.
          # <space>ss: find text in the current buffer.
          "space space" = "file_finder::Toggle";
          "space f f" = "file_finder::Toggle";
          "space /" = "text_finder::Toggle";
          "space s g" = "text_finder::Toggle";
          "space s s" = "buffer_search::Deploy";
          "space s r" = "buffer_search::DeployReplace";
        };
      }
      {
        # Keep the same leader finders available from an empty Zed pane.
        context = "EmptyPane || SharedScreen";
        bindings = {
          "space space" = "file_finder::Toggle";
          "space f f" = "file_finder::Toggle";
          "space /" = "text_finder::Toggle";
          "space s g" = "text_finder::Toggle";
        };
      }
      {
        # Override Zed's finder defaults: keep ctrl-j/k/l for moving/choosing
        # in the picker, and use alt-h/j/k/l when you want to open the selected
        # item in a split direction. Alt-left/right and ctrl-alt-h/l are kept as
        # fallbacks because some Linux menu/toolkit paths can steal bare Alt+h/l.
        context = "FileFinder || (FileFinder > Picker > Editor) || (FileFinder > Picker > menu)";
        bindings = {
          "ctrl-j" = "menu::SelectNext";
          "ctrl-k" = "menu::SelectPrevious";
          "ctrl-l" = "menu::Confirm";
          "alt-h" = "pane::SplitLeft";
          "alt-j" = "pane::SplitDown";
          "alt-k" = "pane::SplitUp";
          "alt-l" = "pane::SplitRight";
          "alt-left" = "pane::SplitLeft";
          "alt-down" = "pane::SplitDown";
          "alt-up" = "pane::SplitUp";
          "alt-right" = "pane::SplitRight";
          "ctrl-alt-h" = "pane::SplitLeft";
          "ctrl-alt-l" = "pane::SplitRight";
        };
      }
      {
        context = "TextFinder || (TextFinder > Picker > Editor) || (TextFinder > Picker > menu)";
        bindings = {
          "ctrl-j" = "menu::SelectNext";
          "ctrl-k" = "menu::SelectPrevious";
          "ctrl-l" = "menu::Confirm";
          "alt-h" = "pane::SplitLeft";
          "alt-j" = "pane::SplitDown";
          "alt-k" = "pane::SplitUp";
          "alt-l" = "pane::SplitRight";
          "alt-left" = "pane::SplitLeft";
          "alt-down" = "pane::SplitDown";
          "alt-up" = "pane::SplitUp";
          "alt-right" = "pane::SplitRight";
          "ctrl-alt-h" = "pane::SplitLeft";
          "ctrl-alt-l" = "pane::SplitRight";
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
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-j" = "workspace::ActivatePaneDown";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-l" = "workspace::ActivatePaneRight";
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
