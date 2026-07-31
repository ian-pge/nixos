{
  programs.zed-editor = {
    enable = true;
    mutableUserSettings = false;
    # Keep keymap.json declarative too; mutable mode merges old entries and
    # leaves removed shortcuts active in text-input contexts.
    mutableUserKeymaps = false;

    # This whole block is rendered to ~/.config/zed/settings.json
    userSettings = {
      disable_ai = false;
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
        enabled = true;
        button = true;
        # Keep the Agent Panel next to the Threads Sidebar.
        dock = "left";
        sidebar_side = "left";
        # Let conversations follow the full width of the Agent Panel.
        limit_content_width = false;
        # Keep reasoning, file edits, and terminal output compact by default.
        thinking_display = "preview";
        expand_edit_card = false;
        expand_terminal_card = false;
        show_turn_stats = true;
        # Notify when an agent finishes or needs input, and make the
        # notification audible even when Zed is in the background.
        notify_when_agent_waiting = "primary_screen";
        play_sound_when_agent_done = "always";
        # Do not add Zed-side confirmation prompts on top of the external
        # agents' own permission modes.
        tool_permissions = {
          default = "allow";
        };
        commit_message_model = {
          provider = "openai-subscribed";
          model = "gpt-5.6-luna";
        };
      };

      # Install Claude Agent and Codex from Zed's ACP registry.
      agent_servers = {
        "claude-acp" = {
          type = "registry";
          default_mode = "bypassPermissions";
        };
        "codex-acp" = {
          type = "registry";
          # Apply full access both through Zed's ACP session selection and at
          # Codex ACP process startup, so every new thread begins in this mode.
          default_mode = "agent-full-access";
          env = {
            INITIAL_AGENT_MODE = "agent-full-access";
          };
        };
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
      # Panel visibility is stored with the session, so restore it when Zed
      # starts instead of recreating an empty layout with closed panels.
      restore_on_startup = "last_session";

      tabs = {
        git_status = true;
        file_icons = true;
      };

      title_bar = {
        show_branch_status_icon = true;
      };

      search = {
        button = false;
      };

      status_bar = {
        show_active_file = true;
      };

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
      cursor_blink = true;
      theme_overrides = {
        "Catppuccin Macchiato (sapphire)" = {
          players = [
            {
              cursor = "#ffcc33";
            }
          ];
        };
      };
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
        dock = "right";
      };

      git_panel = {
        dock = "right";
        file_icons = true;
      };

      outline_panel = {
        # This completes Zed's agentic layout: agent surfaces on the left,
        # editor-oriented panels on the right.
        dock = "right";
        button = false;
      };

      collaboration_panel = {
        dock = "right";
        button = false;
      };

      terminal = {
        font_family = "JetBrainsMono Nerd Font";
        font_fallbacks = ["Iosevka"];
        dock = "right";
        font_size = 14;
        blinking = "on";
        show_count_badge = true;
        copy_on_select = true;
        line_height = "standard";
        toolbar = {
          breadcrumbs = true;
        };
      };

      buffer_font_family = "JetBrainsMono Nerd Font";
      buffer_font_fallbacks = ["Iosevka"];
      buffer_font_size = 16;

      ui_font_family = "Ubuntu Nerd Font";
      ui_font_fallbacks = ["Iosevka"];
      ui_font_size = 16;
    };
    userKeymaps = [
      {
        # Global Agent workspace shortcuts: Shift+Space, then A, then the
        # action key. This keeps the leader available in every Zed surface.
        bindings = {
          "ctrl-space" = "workspace::ToggleZoom";
          "shift-space a a" = "agent::ToggleFocus";
          "shift-space a t" = "multi_workspace::ToggleWorkspaceSidebar";
          "shift-space a f" = "multi_workspace::FocusWorkspaceSidebar";
          "shift-space a w" = [
            "git::CreateWorktree"
            {
              worktree_name = null;
              branch_target.kind = "current_branch";
            }
          ];
          "shift-space a c" = [
            "agent::NewExternalAgentThread"
            {agent = "claude-acp";}
          ];
          "shift-space a x" = [
            "agent::NewExternalAgentThread"
            {agent = "codex-acp";}
          ];
          "shift-space a enter" = "agent::NewTerminalThread";
          # Git workflow: Shift+Space, then G, then the action key.
          "shift-space g g" = "git_panel::ToggleFocus";
          "shift-space g s" = "git::StageAll";
          "shift-space g p" = "git::Push";
          "shift-space g c" = "git::ExpandCommitEditor";
          "shift-space g m" = "git::GenerateCommitMessage";
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
        context = "AcpThread";
        bindings = {
          # Scroll the active Agent response by three lines.
          "ctrl-j" = "agent::ScrollOutputLineDown";
          "ctrl-k" = "agent::ScrollOutputLineUp";
        };
      }
      {
        # VimControl only exists in normal, visual, and operator modes.
        context = "VimControl && !menu";
        bindings = {
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-j" = "workspace::ActivatePaneDown";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-l" = "workspace::ActivatePaneRight";
        };
      }
      {
        # Insert and replace modes do not expose VimControl, so target their
        # vim_mode value directly to keep pane navigation available while typing.
        context = "Editor && (vim_mode == insert || vim_mode == replace) && !menu";
        bindings = {
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-j" = "workspace::ActivatePaneDown";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-l" = "workspace::ActivatePaneRight";
        };
      }
      {
        # Space-based leaders stay limited to normal mode so an ordinary
        # space never starts a shortcut while typing.
        context = "VimControl && vim_mode == normal && !menu";
        bindings = {
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
        # In an Agent message editor, Ctrl+j/k always scroll the conversation,
        # regardless of the current Vim mode.
        context = "AcpThread > MessageEditor > Editor && !menu";
        bindings = {
          "ctrl-j" = "agent::ScrollOutputLineDown";
          "ctrl-k" = "agent::ScrollOutputLineUp";
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
        # Threads Sidebar is not a regular dock, so include its context
        # explicitly to make Ctrl+l return to the workspace.
        context = "Dock || ThreadsSidebar";
        bindings = {
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-j" = "workspace::ActivatePaneDown";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-l" = "workspace::ActivatePaneRight";
        };
      }
      {
        context = "ThreadsSidebar";
        bindings = {
          # Native context-sensitive action: archive an agent thread or close
          # a terminal thread, depending on the selected sidebar entry.
          "ctrl-w" = "agent::ArchiveSelectedThread";
          # Keep the native Shift+Backspace archive shortcut disabled to avoid
          # accidental archiving.
          "shift-backspace" = null;
        };
      }
      {
        context = "ThreadsArchiveView";
        bindings = {
          "shift-backspace" = null;
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
