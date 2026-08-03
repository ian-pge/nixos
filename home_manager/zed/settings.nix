{
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
    # Surface Zed's native agent action whenever Git reports conflicts.
    show_merge_conflict_indicator = true;
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

  # Let rendered Markdown previews use the full width of their pane.
  markdown_preview = {
    limit_content_width = false;
  };

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
}
