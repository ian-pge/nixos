{pkgs}: let
  createWorktreeHook = pkgs.writeShellApplication {
    name = "zed-create-worktree-hook";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.gnused
    ];
    text = ''
      set -uo pipefail

      fail() {
        printf 'create_worktree: erreur: %s\n' "$*" >&2
        exit 1
      }

      [[ -n "''${ZED_WORKTREE_ROOT:-}" ]] || fail "ZED_WORKTREE_ROOT n'est pas défini"
      [[ -n "''${ZED_MAIN_GIT_WORKTREE:-}" ]] || fail "ZED_MAIN_GIT_WORKTREE n'est pas défini"

      worktree_root="''${ZED_WORKTREE_ROOT%/}"
      main_worktree="''${ZED_MAIN_GIT_WORKTREE%/}"

      git -C "$worktree_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || fail "le nouveau worktree n'est pas un dépôt Git: $worktree_root"
      git -C "$main_worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || fail "le worktree principal n'est pas un dépôt Git: $main_worktree"

      # Zed may already have created a branch. Only repair detached worktrees.
      if git -C "$worktree_root" symbolic-ref --quiet HEAD >/dev/null 2>&1; then
        exit 0
      fi

      # Keep the exact detached commit selected by branch_target=current_branch
      # as the base, even if the main worktree moves while this hook is running.
      base_commit="$(git -C "$worktree_root" rev-parse --verify HEAD)" \
        || fail "impossible de déterminer le commit de base"
      worktree_leaf="$(basename -- "$worktree_root")"
      main_worktree_leaf="$(basename -- "$main_worktree")"
      if [[ "$worktree_root" != "$main_worktree" && "$worktree_leaf" == "$main_worktree_leaf" ]]; then
        # For multi-workspace projects, Zed nests each repository below the
        # generated worktree name: .../<worktree-name>/<repository-name>.
        raw_name="$(basename -- "$(dirname -- "$worktree_root")")"
      else
        raw_name="$worktree_leaf"
      fi
      normalized="$(
        printf '%s' "$raw_name" \
          | LC_ALL=C sed -E \
            -e 's/[^A-Za-z0-9._-]+/-/g' \
            -e 's/\.\.+/-/g' \
            -e 's/^[.-]+//' \
            -e 's/[.-]+$//' \
            -e 's/\.lock$//' \
          | cut -c 1-120 \
          | sed -E -e 's/[.-]+$//' -e 's/\.lock$//'
      )"
      [[ -n "$normalized" ]] || normalized="worktree"

      base_branch="agent/$normalized"
      branch="$base_branch"
      suffix=2

      while true; do
        if git -C "$main_worktree" show-ref --verify --quiet "refs/heads/$branch"; then
          branch="$base_branch-$suffix"
          suffix=$((suffix + 1))
          continue
        fi

        git check-ref-format --branch "$branch" >/dev/null 2>&1 \
          || fail "nom de branche invalide après normalisation: $branch"

        if git -C "$worktree_root" switch --create "$branch" "$base_commit"; then
          printf 'create_worktree: branche %s créée depuis %s\n' "$branch" "$base_commit"
          exit 0
        fi

        # A concurrent hook may have won the race after show-ref. In that
        # specific case, retry with the next suffix; otherwise keep the Git
        # error visible in Zed's terminal.
        if git -C "$main_worktree" show-ref --verify --quiet "refs/heads/$branch"; then
          branch="$base_branch-$suffix"
          suffix=$((suffix + 1))
          continue
        fi

        fail "impossible de créer la branche $branch"
      done
    '';
  };
in {
  label = "Create agent branch for detached worktree";
  command = "${createWorktreeHook}/bin/zed-create-worktree-hook";
  cwd = "$ZED_WORKTREE_ROOT";
  hooks = ["create_worktree"];
  reveal = "no_focus";
  hide = "on_success";
}
