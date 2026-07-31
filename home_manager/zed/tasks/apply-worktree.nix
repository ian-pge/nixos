{finishWorktreeCommand}: {
  label = "Apply agent worktree";
  command = "${finishWorktreeCommand}/bin/zed-finish-worktree";
  cwd = "$ZED_WORKTREE_ROOT";
  reveal = "no_focus";
  hide = "on_success";
  allow_concurrent_runs = false;
}
