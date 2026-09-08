{...}: {
  imports = [./services/playwright-mcp.nix];

  programs.zed-editor = {
    enable = true;

    # Keep Zed's generated JSON fully declarative.
    mutableUserSettings = false;
    mutableUserKeymaps = false;
    mutableUserTasks = false;

    userSettings = import ./settings.nix;
    userKeymaps = import ./keymaps.nix;
    userTasks = [];
  };
}
