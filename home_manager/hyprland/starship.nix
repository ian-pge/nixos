{
  programs.fish.functions = {
    starship_transient_prompt_func.body = ''starship module time'';
    prompt_newline = {
      onEvent = "fish_postexec";
      body = ''echo'';
    };
  };

  # ── Starship ──────────────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableTransience = true;

    settings = {
      right_format = "$cmd_duration";
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
        rosewater = "#f4dbd6"; # <-- fixed
        maroon = "#ee99a0";
        teal = "#8bd5ca";
      };

      # include $time and $container so they actually show
      format = ''
        $os $username@$hostname $directory $git_branch$container$line_break$character
      '';
      add_newline = false;

      time = {
        disabled = false;
        time_format = "%H:%M";
        style = "fg:yellow";
        format = "[$time]($style) ";
      };

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

      username = {
        show_always = true;
        style_user = "fg:pink";
        style_root = "fg:red";
        format = "[$user]($style)";
      };

      hostname = {
        ssh_only = false;
        style = "fg:mauve";
        format = "[$hostname]($style)";
      };

      directory = {
        truncation_length = 0;
        truncate_to_repo = false;
        home_symbol = "~";
        style = "fg:flamingo";
        repo_root_style = "fg:teal";
        read_only = " ";
        read_only_style = "fg:flamingo";
        repo_root_read_only_style = "fg:teal";
        repo_root_format = "[$read_only]($repo_root_read_only_style)[$before_root_path]($repo_root_style)[$repo_root]($repo_root_style)[$path]($repo_root_style)";
        format = "[$read_only]($read_only_style)[$path]($style)";
      };

      git_branch = {
        symbol = " ";
        style = "fg:teal";
        format = "[$symbol$branch]($style) ";
      };

      container = {
        symbol = " ";
        style = "fg:maroon";
        format = "[$symbol$container]($style) ";
      };

      character = {
        success_symbol = "[❯](green)";
        error_symbol = "[❯](fg:red)";
        vimcmd_symbol = "[❮](fg:peach)";
        vimcmd_visual_symbol = "[❮](fg:mauve)";
        vimcmd_replace_symbol = "[❮](fg:sky)";
        vimcmd_replace_one_symbol = "[❮](fg:pink)";
      };

      cmd_duration = {
        min_time = 0;
        show_milliseconds = true;
        style = "fg:peach";
        format = "[$duration]($style)";
      };
    };
  };
}
