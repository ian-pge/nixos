{
  programs.fish.functions = {
    # This overrides the default bold–green ❯ Starship shows in old prompts.
    starship_transient_prompt_func.body = ''
      starship module time
    '';
    # Right side of the transient prompt stays empty, matching OMP behaviour.
  };

  # ── Starship ──────────────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableFishIntegration = true; # puts `starship init fish | source` in config
    enableTransience = true;

    settings = {
      # ─ Global options ─────────────────────────────────────────────────────────
      add_newline = true; # first line (time-os-path …) ↩︎ second line (❯)
      right_format = "$cmd_duration"; # right-prompt → 27 ms

      # Palette (same hex codes you used in Oh-My-Posh) ─────────────────────────
      palette = "catppuccin";

      palettes.catppuccin = {
        blue = "#8AADF4";
        green = "#a6da95";
        lavender = "#B7BDF8";
        mauve = "#c6a0f6";
        os = "#ACB0BE";
        peach = "#F5A97F";
        pink = "#F5BDE6";
        sapphire = "#7dc4e4";
        yellow = "#eed49f";
        sky = "#91d7e3";
        flamingo = "#f0c6c6";
        rosewater = "#4dbd6";
        maroon = "#ee99a0";
      };

      # ─ What gets printed on the left prompt line ─────────────────────────────
      format = ''
        $os $username@$hostname $directory $git_branch$line_break$character
      '';

      # 1 • Current time (18:49) -------------------------------------------------
      time = {
        disabled = false;
        time_format = "%H:%M";
        style = "fg:yellow";
        format = "[$time]($style) "; # trailing space ␠
      };

      # 2 • OS icon (snow-flake Nix) --------------------------------------------
      os = {
        disabled = false;
        style = "fg:sky";
        format = "[$symbol]($style)";
        symbols = {
          NixOS = "";
          Ubuntu = "";
          Arch = "";
          Fedora = "";
          Debian = "";
        };
      };

      # 3 • user@host ------------------------------------------------------------
      username = {
        show_always = true;
        style_user = "fg:green";
        style_root = "fg:red";
        format = "[$user]($style)";
      };
      hostname = {
        ssh_only = false;
        style = "fg:mauve";
        format = "[$hostname]($style)"; # trailing space
      };

      # 4 • Path (“~/workspace/…”) ----------------------------------------------
      directory = {
        truncation_length = 0;
        truncate_to_repo = false;
        home_symbol = "~";
        style = "fg:flamingo";
        read_only = " ";
        read_only_style = "fg:flamingo";
        format = "[$read_only]($read_only_style)[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)";
        before_repo_root_style = "fg:flamingo";
        repo_root_style = "fg:maroon";
      };

      # 5 • Git HEAD -------------------------------------------------------------
      git_branch = {
        symbol = " ";
        style = "fg:maroon";
        format = "[$symbol$branch]($style) ";
      };

      # ── second line: prompt symbol ❯  ─────────────────────────────────────────
      character = {
        success_symbol = "[❯](green)";
        error_symbol = "[❯](fg:red)";
        vimcmd_symbol = "[❮](fg:peach)";
        vimcmd_visual_symbol = "[❮](fg:mauve)";
        vimcmd_replace_symbol = "[❮](fg:sky)";
        vimcmd_replace_one_symbol = "[❮](fg:pink)";
      };

      # ── right prompt: elapsed time (27 ms) ───────────────────────────────────
      cmd_duration = {
        min_time = 0; # always display
        show_milliseconds = true;
        style = "fg:peach";
        format = "[$duration]($style)";
      };
    };
  };
}
