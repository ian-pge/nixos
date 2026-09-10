{
  config,
  pkgs,
  ...
}: let
  markdownTheme = import ./markdown-theme.nix;
  markdownThemeOverrides =
    (pkgs.formats.json {}).generate
    "zed-markdown-theme-overrides.json"
    markdownTheme;
in {
  imports = [./services/playwright-mcp.nix];

  xdg.configFile."zed/themes/catppuccin-markdown.json".source =
    pkgs.runCommand "zed-catppuccin-markdown.json" {
      nativeBuildInputs = [pkgs.jq];
    } ''
      jq --slurpfile custom ${markdownThemeOverrides} '
        .name = $custom[0].name
        | .themes = [
            .themes[]
            | select(.name == "Catppuccin Macchiato (sapphire)")
            | . * $custom[0]
          ]
        | if (.themes | length) == 1 then .
          else error("Catppuccin Macchiato base theme not found") end
      ' ${config.xdg.configFile."zed/themes/catppuccin.json".source} > "$out"
    '';

  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor;

    # Keep Zed's generated JSON fully declarative.
    mutableUserSettings = false;
    mutableUserKeymaps = false;
    mutableUserTasks = false;

    userSettings = import ./settings.nix;
    userKeymaps = import ./keymaps.nix;
    userTasks = [];
  };
}
