{pkgs, ...}: let
  yaziOpen = pkgs.writeShellScriptBin "yazi-open" ''
    # Debug logging used while fixing this wrapper; left here for easy re-enable:
    # log_dir="$HOME/.cache/yazi-open"
    # mkdir -p "$log_dir"
    # log_file="$log_dir/debug.log"
    # exec 3>>"$log_file"
    # log() { printf '%s [pid=%s] %s\n' "$(date --iso-8601=ns)" "$$" "$*" >&3; }

    tmp="$(${pkgs.coreutils}/bin/mktemp -t yazi-chooser.XXXXXX)"
    cleanup() {
      ${pkgs.coreutils}/bin/rm -f -- "$tmp"
    }
    trap cleanup EXIT

    ${pkgs.yazi}/bin/yazi "$@" --chooser-file="$tmp"

    run_in_uwsm() {
      unit="yazi-$1-$(${pkgs.coreutils}/bin/date +%s)-$$.scope"
      shift

      # UWSM is the native launcher for this Hyprland session; it creates a
      # user-systemd scope with the right graphical session environment.
      ${pkgs.util-linux}/bin/setsid -f ${pkgs.uwsm}/bin/uwsm app -u "$unit" -S both -- "$@" >/dev/null 2>&1
    }

    open_with_zed() {
      run_in_uwsm zed ${pkgs.zed-editor}/bin/zeditor --new "$1"
    }

    open_with_default_app() {
      path="$1"
      mime="$(${pkgs.file}/bin/file --brief --mime-type -- "$path" 2>/dev/null || true)"

      case "$mime" in
        image/*)
          run_in_uwsm oculante ${pkgs.oculante}/bin/oculante "$path"
          ;;
        application/pdf)
          run_in_uwsm zathura ${pkgs.zathura}/bin/zathura "$path"
          ;;
        video/*)
          run_in_uwsm mpv ${pkgs.mpv}/bin/mpv "$path"
          ;;
        *)
          run_in_uwsm xdg-open \
            ${pkgs.coreutils}/bin/env -u NIXOS_XDG_OPEN_USE_PORTAL -u GTK_USE_PORTAL \
            ${pkgs.xdg-utils}/bin/xdg-open "$path"
          ;;
      esac
    }

    is_code_file() {
      path="$1"
      mime="$(${pkgs.file}/bin/file --brief --mime-type -- "$path" 2>/dev/null || true)"

      case "$mime" in
        text/*|application/json|application/*+json|application/xml|application/*+xml|application/x-yaml|application/toml|application/x-shellscript)
          return 0
          ;;
      esac

      case "$path" in
        *.astro|*.c|*.cc|*.clj|*.cljs|*.conf|*.cpp|*.cs|*.css|*.dart|*.diff|*.dockerfile|*.elm|*.ex|*.exs|*.fish|*.go|*.h|*.hpp|*.hs|*.html|*.java|*.js|*.jsx|*.kt|*.lua|*.md|*.nix|*.patch|*.php|*.pl|*.prisma|*.py|*.r|*.rb|*.rs|*.scss|*.sh|*.sql|*.svelte|*.swift|*.tf|*.toml|*.ts|*.tsx|*.vue|*.yaml|*.yml|*.zig)
          return 0
          ;;
      esac

      return 1
    }

    if [ -s "$tmp" ]; then
      opened_file="$(${pkgs.coreutils}/bin/head -n 1 "$tmp")"

      if [ -d "$opened_file" ] || is_code_file "$opened_file"; then
        open_with_zed "$opened_file"
      else
        open_with_default_app "$opened_file"
      fi
    fi
  '';
in {
  home.packages = [yaziOpen];

  programs.yazi = {
    enable = true;
    shellWrapperName = "yy";
    enableFishIntegration = true;

    plugins = {
      mount = pkgs.yaziPlugins.mount;
    };

    keymap.mgr.prepend_keymap = [
      {
        # In picker mode, Yazi exits when the normal `open` action fires.
        # Keep `o` as a non-picker open action so Yazi stays open.
        on = "o";
        run = ''shell --orphan -- ${pkgs.coreutils}/bin/env -u NIXOS_XDG_OPEN_USE_PORTAL -u GTK_USE_PORTAL ${pkgs.xdg-utils}/bin/xdg-open "$0"'';
        desc = "Open hovered item with default app without quitting";
      }
      {
        on = "M";
        run = "plugin mount";
        desc = "Open mount manager";
      }
    ];
  };
}
