{
  lib,
  pkgs,
}: let
  rebaseAgentPrompt = builtins.concatStringsSep " " [
    "L'Apply direct de ce worktree a été refusé parce que la branche principale a avancé."
    "Rebase la branche agent courante sur la branche actuellement ouverte dans le worktree principal."
    "Résous les conflits seulement lorsque l'intention est claire et pose-moi une question avant d'agir dès qu'un choix est ambigu ou peut modifier le résultat attendu."
    "Relance ensuite les tests pertinents et laisse la branche agent propre avec tous les changements utiles commités."
    "Ne modifie pas manuellement le worktree principal, ne force aucune opération Git et ne supprime rien toi-même."
    "Quand le rebase et les tests ont réussi, exécute zed-finish-worktree comme toute dernière commande; elle effectuera seule l'Apply sécurisé et le nettoyage."
    "Si cette commande échoue, ne contourne aucune vérification et explique-moi le problème."
  ];
  rebaseAgentUrl = "zed://agent?prompt=${lib.escapeURL rebaseAgentPrompt}";
in
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

      open_rebase_agent() {
        printf '%s\n' \
          "zed-finish-worktree: la branche principale a avancé; ouverture d'un agent de rebase"
        zeditor "${rebaseAgentUrl}" \
          || fail "impossible d'ouvrir l'agent chargé du rebase"
        exit 0
      }

      agent_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" \
        || fail "la commande doit être lancée depuis un worktree Git"
      agent_root="$(realpath -e -- "$agent_root")" \
        || fail "impossible de résoudre le chemin du worktree courant"

      agent_branch="$(git -C "$agent_root" symbolic-ref --quiet --short HEAD)" \
        || fail "le worktree courant est en detached HEAD"
      case "$agent_branch" in
        agent/*) ;;
        *) fail "refus de traiter la branche non-agent '$agent_branch'" ;;
      esac

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

      git -C "$main_root" merge-base --is-ancestor "$main_head" "$agent_head" \
        || open_rebase_agent

      # Recheck both refs immediately before the mutation so a concurrent update
      # cannot silently invalidate the state that was just validated.
      [[ "$(git -C "$main_root" rev-parse --verify HEAD)" == "$main_head" ]] \
        || open_rebase_agent
      [[ "$(git -C "$agent_root" rev-parse --verify HEAD)" == "$agent_head" ]] \
        || fail "$agent_branch a avancé pendant les vérifications; recommence la préparation"

      printf 'zed-finish-worktree: fusion ff-only de %s dans %s\n' "$agent_branch" "$main_branch"
      if ! git -C "$main_root" merge --ff-only --no-edit "refs/heads/$agent_branch"; then
        latest_main_head="$(git -C "$main_root" rev-parse --verify HEAD)" \
          || fail "le merge ff-only a échoué et le nouveau HEAD principal est illisible"
        git -C "$main_root" merge-base --is-ancestor "$latest_main_head" "$agent_head" \
          || open_rebase_agent
        fail "le merge ff-only a échoué; aucun nettoyage n'a été effectué"
      fi

      merged_head="$(git -C "$main_root" rev-parse --verify HEAD)" \
        || fail "le merge a réussi mais le nouveau HEAD est illisible; aucun nettoyage n'a été effectué"
      [[ "$merged_head" == "$agent_head" ]] \
        || fail "la branche principale n'est pas au commit validé; aucun nettoyage n'a été effectué"
      if [[ -n "$(git -C "$main_root" status --porcelain=v1 --untracked-files=all)" ]]; then
        show_status "$main_root"
        fail "le merge a réussi mais le worktree principal n'est pas propre; aucun nettoyage n'a été effectué"
      fi

      # Leave the directory before removing it. Never force either deletion:
      # Git remains the final authority on whether cleanup is safe.
      cd "$main_root"
      git worktree remove -- "$agent_root" \
        || fail "le merge a réussi, mais Git a refusé de supprimer le worktree agent"
      git branch --delete -- "$agent_branch" \
        || fail "le worktree a été supprimé, mais Git a refusé de supprimer la branche $agent_branch"

      printf 'zed-finish-worktree: succès: %s intégré dans %s; worktree et branche supprimés\n' \
        "$agent_branch" "$main_branch"
      zeditor --reuse "$main_root" \
        || fail "l'intégration a réussi, mais Zed n'a pas pu réutiliser la fenêtre pour le worktree principal: $main_root"
    '';
  }
