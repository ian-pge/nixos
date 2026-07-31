{
  lib,
  pkgs,
  ...
}: let
  createWorktreeTask = import ./tasks/create-worktree.nix {inherit pkgs;};
  finishWorktreeCommand = import ./commands/finish-worktree.nix {inherit lib pkgs;};
  applyWorktreeTask = import ./tasks/apply-worktree.nix {inherit finishWorktreeCommand;};
in {
  home.packages = [finishWorktreeCommand];

  programs.zed-editor = {
    enable = true;

    # Keep Zed's generated JSON fully declarative.
    mutableUserSettings = false;
    mutableUserKeymaps = false;
    mutableUserTasks = false;

    userSettings = import ./settings.nix;
    userKeymaps = import ./keymaps.nix;
    userTasks = [
      createWorktreeTask
      applyWorktreeTask
    ];
  };
}
