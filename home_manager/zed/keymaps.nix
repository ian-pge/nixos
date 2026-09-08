[
  {
    # Reserve Ctrl+A/F/G as global leaders.
    bindings = {
      "ctrl-space" = "workspace::ToggleZoom";
      "ctrl-e" = "project_panel::Toggle";
      # Invoke the Inline Assistant from every Zed surface that supports it.
      "alt-tab" = "assistant::InlineAssist";
      "ctrl-a a" = "agent::Toggle";
      "ctrl-t" = "multi_workspace::ToggleWorkspaceSidebar";
      "ctrl-a c" = [
        "agent::NewExternalAgentThread"
        {agent = "claude-acp";}
      ];
      "ctrl-a x" = [
        "agent::NewExternalAgentThread"
        {agent = "codex-acp";}
      ];
      "ctrl-a enter" = "agent::NewTerminalThread";
      # Fuzzy finders: Ctrl+F, then Space or Slash.
      "ctrl-f space" = "file_finder::Toggle";
      "ctrl-f /" = "text_finder::Toggle";
      # Git workflow: Ctrl+G, then the action key.
      "ctrl-g g" = "git_panel::Toggle";
      "ctrl-g s" = "git::StageAll";
      "ctrl-g p" = "git::Push";
      "ctrl-g c" = [
        "action::Sequence"
        [
          "git::ExpandCommitEditor"
          [
            "workspace::SendKeystrokes"
            "alt-l"
          ]
        ]
      ];
      "ctrl-g m" = "git::GenerateCommitMessage";
      "ctrl-enter" = "terminal_panel::Toggle";
      "shift-escape" = null;
    };
  }
  # Remove every native single-key action attached to the three leaders.
  # Unlike a null binding, `unbind` leaves longer key sequences functional.
  {
    unbind = {
      "ctrl-a" = "editor::SelectAll";
      "ctrl-f" = "buffer_search::Deploy";
      "ctrl-g" = "go_to_line::Toggle";
      "ctrl-t" = "project_symbols::Toggle";
    };
  }
  {
    unbind = {
      "ctrl-a" = "vim::Increment";
      "ctrl-f" = "vim::PageDown";
      "ctrl-g" = "vim::ShowLocation";
      "ctrl-t" = "pane::GoToOlderTag";
    };
  }
  {
    unbind = {
      "ctrl-f" = "agent::ToggleSearch";
      "ctrl-g" = "agents_sidebar::ToggleThreadHistory";
      "ctrl-t" = "debugger::ToggleThreadPicker";
    };
  }
  {
    unbind = {
      "ctrl-f" = "search::FocusSearch";
      "ctrl-t" = "keymap_editor::ShowMatchingKeybinds";
    };
  }
  {
    unbind = {
      "ctrl-f" = "agents_sidebar::FocusSidebarFilter";
      "ctrl-t" = "vim::Indent";
    };
  }
  {
    # The Git Panel has its own contextual Ctrl+Enter binding, which takes
    # precedence over the global terminal shortcut. Override it here while
    # leaving the more specific commit-editor contexts below untouched.
    context = "GitPanel";
    bindings = {
      "ctrl-enter" = "terminal_panel::Toggle";
    };
  }
  {
    context = "CommitEditor > Editor";
    bindings = {
      "ctrl-enter" = "git::Commit";
    };
  }
  {
    context = "GitCommit > Editor";
    bindings = {
      "ctrl-enter" = "git::Commit";
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
      # <space>ff: find files by name.
      # <space>sg: find text across the project.
      # <space>ss: find text in the current buffer.
      "space f f" = "file_finder::Toggle";
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
      "space f f" = "file_finder::Toggle";
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
      "ctrl-n" = "workspace::NewTerminal";
      "ctrl-y" = "terminal::ScrollLineUp";
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
]
