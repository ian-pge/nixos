{pkgs}:
pkgs.writeShellApplication {
  name = "zed-finish-worktree";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.git
    pkgs.zed-editor
  ];
  text = ''
    set -uo pipefail

    fail() {
      printf 'zed-finish-worktree: erreur: %s\n' "$*" >&2
      exit 1
    }

    show_status() {
      local worktree="$1"
      git -C "$worktree" status --short --branch >&2 || true
    }

    find_rebase_dir() {
      local git_dir="$1"

      if [[ -d "$git_dir/rebase-merge" ]]; then
        printf '%s\n' "$git_dir/rebase-merge"
      elif [[ -d "$git_dir/rebase-apply" ]]; then
        printf '%s\n' "$git_dir/rebase-apply"
      fi
    }

    branch_from_rebase() {
      local rebase_dir="$1"
      local head_name

      [[ -r "$rebase_dir/head-name" ]] \
        || fail "le rebase en cours n'indique pas sa branche d'origine"
      IFS= read -r head_name < "$rebase_dir/head-name" \
        || fail "impossible de lire la branche du rebase en cours"
      case "$head_name" in
        refs/heads/agent/*) printf '%s\n' "''${head_name#refs/heads/}" ;;
        *) fail "refus de reprendre le rebase de la branche '$head_name'" ;;
      esac
    }

    has_conflict_markers() {
      local worktree="$1"
      local path line
      shift

      for path in "$@"; do
        [[ -f "$worktree/$path" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
          case "$line" in
            "<<<<<<< "* | "||||||| "* | "=======" | ">>>>>>> "*)
              printf 'zed-finish-worktree: marqueur de conflit restant dans %s\n' "$path" >&2
              return 0
              ;;
          esac
        done < "$worktree/$path"
      done
      return 1
    }

    stop_for_zed_conflicts() {
      local worktree="$1"

      show_status "$worktree"
      printf '%s\n' \
        "zed-finish-worktree: résous les conflits avec le bouton natif de Zed, teste le résultat, puis relance Shift+Space A F" >&2
      exit 1
    }

    agent_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" \
      || fail "la commande doit être lancée depuis un worktree Git"
    agent_root="$(realpath -e -- "$agent_root")" \
      || fail "impossible de résoudre le chemin du worktree courant"

    agent_git_dir="$(git -C "$agent_root" rev-parse --absolute-git-dir)" \
      || fail "impossible d'identifier le répertoire Git du worktree courant"
    rebase_dir="$(find_rebase_dir "$agent_git_dir")"
    if [[ -n "$rebase_dir" ]]; then
      agent_branch="$(branch_from_rebase "$rebase_dir")" \
        || fail "impossible d'identifier la branche du rebase en cours"
    else
      agent_branch="$(git -C "$agent_root" symbolic-ref --quiet --short HEAD)" \
        || fail "le worktree courant est en detached HEAD"
      case "$agent_branch" in
        agent/*) ;;
        *) fail "refus de traiter la branche non-agent '$agent_branch'" ;;
      esac
    fi

    main_root=""
    while IFS= read -r -d "" entry; do
      case "$entry" in
        "worktree "*)
          main_root="''${entry#worktree }"
          break
          ;;
      esac
    done < <(git -C "$agent_root" worktree list --porcelain -z)
    [[ -n "$main_root" ]] || fail "impossible d'identifier le worktree principal"
    main_root="$(realpath -e -- "$main_root")" \
      || fail "le worktree principal n'existe plus: $main_root"
    [[ "$agent_root" != "$main_root" ]] \
      || fail "cette commande doit être lancée depuis un worktree agent, pas depuis le worktree principal"

    main_branch="$(git -C "$main_root" symbolic-ref --quiet --short HEAD)" \
      || fail "le worktree principal est en detached HEAD"

    if [[ -n "$rebase_dir" ]]; then
      if [[ -n "$(git -C "$main_root" status --porcelain=v1 --untracked-files=all)" ]]; then
        show_status "$main_root"
        fail "le worktree principal n'est pas propre; le rebase agent reste en pause"
      fi

      mapfile -d "" conflicted_paths \
        < <(git -C "$agent_root" diff --name-only --diff-filter=U -z)
      if (( ''${#conflicted_paths[@]} > 0 )); then
        if has_conflict_markers "$agent_root" "''${conflicted_paths[@]}"; then
          fail "des marqueurs de conflit subsistent; retourne dans l'agent Zed"
        fi
        printf 'zed-finish-worktree: validation de %s fichier(s) résolu(s)\n' \
          "''${#conflicted_paths[@]}"
        git -C "$agent_root" add -A -- "''${conflicted_paths[@]}" \
          || fail "impossible de marquer les fichiers conflictuels comme résolus"
      fi

      printf 'zed-finish-worktree: reprise du rebase de %s\n' "$agent_branch"
      if ! GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true git -C "$agent_root" rebase --continue; then
        if [[ -n "$(git -C "$agent_root" diff --name-only --diff-filter=U)" ]]; then
          stop_for_zed_conflicts "$agent_root"
        fi
        show_status "$agent_root"
        fail "la poursuite du rebase a échoué sans nouveau conflit détecté"
      fi
      rebase_dir="$(find_rebase_dir "$agent_git_dir")"
      [[ -z "$rebase_dir" ]] \
        || fail "Git indique que le rebase est toujours en cours"
      printf 'zed-finish-worktree: rebase repris et terminé\n'
    fi

    integrated=false
    for attempt in 1 2 3 4; do
      current_agent_branch="$(git -C "$agent_root" symbolic-ref --quiet --short HEAD)" \
        || fail "le worktree agent est passé en detached HEAD"
      [[ "$current_agent_branch" == "$agent_branch" ]] \
        || fail "le worktree agent est passé de $agent_branch à $current_agent_branch"
      current_main_branch="$(git -C "$main_root" symbolic-ref --quiet --short HEAD)" \
        || fail "le worktree principal est passé en detached HEAD"
      [[ "$current_main_branch" == "$main_branch" ]] \
        || fail "le worktree principal est passé de $main_branch à $current_main_branch"

      if [[ -n "$(git -C "$agent_root" status --porcelain=v1 --untracked-files=all)" ]]; then
        show_status "$agent_root"
        fail "le worktree agent n'est pas propre; committe ou retire ses changements avant l'intégration"
      fi
      if [[ -n "$(git -C "$main_root" status --porcelain=v1 --untracked-files=all)" ]]; then
        show_status "$main_root"
        fail "le worktree principal n'est pas propre; aucune intégration n'a été tentée"
      fi

      agent_head="$(git -C "$agent_root" rev-parse --verify "refs/heads/$agent_branch")" \
        || fail "impossible de lire la branche $agent_branch"
      main_head="$(git -C "$main_root" rev-parse --verify HEAD)" \
        || fail "impossible de lire la branche $main_branch"

      if ! git -C "$main_root" merge-base --is-ancestor "$main_head" "$agent_head"; then
        printf 'zed-finish-worktree: rebase automatique de %s sur %s (%s), tentative %s/4\n' \
          "$agent_branch" "$main_branch" "$main_head" "$attempt"
        if git -C "$agent_root" rebase "$main_head"; then
          printf 'zed-finish-worktree: rebase automatique réussi\n'
          agent_head="$(git -C "$agent_root" rev-parse --verify "refs/heads/$agent_branch")" \
            || fail "impossible de relire la branche $agent_branch après le rebase"
        else
          if [[ -n "$(git -C "$agent_root" diff --name-only --diff-filter=U)" ]]; then
            stop_for_zed_conflicts "$agent_root"
          fi

          show_status "$agent_root"
          fail "le rebase automatique a échoué sans conflit non résolu; intervention manuelle requise"
        fi
      fi

      # Recheck both refs immediately before the mutation so a concurrent
      # update cannot silently invalidate the state that was just validated.
      if [[ "$(git -C "$main_root" rev-parse --verify HEAD)" != "$main_head" ]]; then
        printf 'zed-finish-worktree: %s a avancé pendant les vérifications; nouvelle tentative\n' \
          "$main_branch"
        continue
      fi
      [[ "$(git -C "$agent_root" rev-parse --verify HEAD)" == "$agent_head" ]] \
        || fail "$agent_branch a avancé pendant les vérifications; recommence l'intégration"

      printf 'zed-finish-worktree: fusion ff-only de %s dans %s\n' "$agent_branch" "$main_branch"
      if git -C "$main_root" merge --ff-only --no-edit "refs/heads/$agent_branch"; then
        integrated=true
        break
      fi

      latest_main_head="$(git -C "$main_root" rev-parse --verify HEAD)" \
        || fail "le merge ff-only a échoué et le nouveau HEAD principal est illisible"
      if [[ "$latest_main_head" != "$main_head" ]]; then
        printf 'zed-finish-worktree: %s a avancé pendant le merge; nouvelle tentative\n' \
          "$main_branch"
        continue
      fi
      fail "le merge ff-only a échoué; le worktree agent est conservé"
    done

    [[ "$integrated" == true ]] \
      || fail "la branche principale a changé trop souvent; recommence l'intégration"

    merged_head="$(git -C "$main_root" rev-parse --verify HEAD)" \
      || fail "le merge a réussi mais le nouveau HEAD est illisible; le worktree agent est conservé"
    [[ "$merged_head" == "$agent_head" ]] \
      || fail "la branche principale n'est pas au commit validé; le worktree agent est conservé"
    if [[ -n "$(git -C "$main_root" status --porcelain=v1 --untracked-files=all)" ]]; then
      show_status "$main_root"
      fail "le merge a réussi mais le worktree principal n'est pas propre; le worktree agent est conservé"
    fi

    printf 'zed-finish-worktree: succès: %s intégré dans %s; archive maintenant le thread dans Zed\n' \
      "$agent_branch" "$main_branch"
    zeditor --existing "$main_root" \
      || fail "l'intégration a réussi, mais Zed n'a pas pu activer le workspace principal: $main_root"
  '';
}
