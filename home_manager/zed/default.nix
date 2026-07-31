{pkgs, ...}: let
  createWorktreeTask = import ./tasks/create-worktree.nix {inherit pkgs;};
in {
  programs.zed-editor = {
    enable = true;

    # Keep Zed's generated JSON fully declarative.
    mutableUserSettings = false;
    mutableUserKeymaps = false;
    mutableUserTasks = false;

    userSettings = import ./settings.nix;
    userKeymaps = import ./keymaps.nix;
    userTasks = [createWorktreeTask];
  };
}
